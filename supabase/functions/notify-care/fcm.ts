// Sending to FCM's HTTP v1 API, and nothing else. Kept apart from index.ts so
// the "who should hear about this" logic there is readable without the OAuth
// and token-hygiene mechanics in the way.

const TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token";
const SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
const SEND_TIMEOUT_MS = 8_000;

// Refresh a minute before the hour is up. Google issues these for 3600s; a
// token that expires between minting and sending would fail the whole call.
const TOKEN_SKEW_SECONDS = 60;

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

/// One message, addressed to a single registration token. `notification`
/// present means Android draws it itself even with the app dead; omitted
/// means data-only, which is what wakes the app silently.
export interface FcmMessage {
  notification?: { title: string; body: string };
  data?: Record<string, string>;
  androidChannelId?: string;
}

/// Per-token outcome. `staleToken` is the field the caller must act on: true
/// means this token will never work again and its row should go.
export type SendResult =
  | { ok: true }
  | { ok: false; staleToken: boolean; detail: string };

/// Raised for anything wrong with *our* setup rather than with a token — a
/// malformed service account, a project with FCM disabled. Distinguished
/// because the response to it is to fix the deployment, never to delete
/// somebody's device row.
export class FcmConfigError extends Error {}

let serviceAccount: ServiceAccount | null = null;
let accessToken: { value: string; expiresAt: number } | null = null;

function loadServiceAccount(): ServiceAccount {
  if (serviceAccount) return serviceAccount;
  const raw = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (!raw) throw new FcmConfigError("FCM_SERVICE_ACCOUNT is not set");
  let parsed: Partial<ServiceAccount>;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new FcmConfigError("FCM_SERVICE_ACCOUNT is not valid JSON");
  }
  if (!parsed.project_id || !parsed.client_email || !parsed.private_key) {
    throw new FcmConfigError("FCM_SERVICE_ACCOUNT is missing project_id/client_email/private_key");
  }
  serviceAccount = parsed as ServiceAccount;
  return serviceAccount;
}

export function fcmProjectId(): string {
  return loadServiceAccount().project_id;
}

/// Turns the PEM in the service-account JSON into a signing key. The PEM
/// arrives with literal `\n` escapes when the secret was set from a shell, and
/// with real newlines when it came from a file, so both are normalised.
async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const body = pem
    .replace(/\\n/g, "\n")
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  let der: Uint8Array;
  try {
    der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  } catch {
    throw new FcmConfigError("FCM_SERVICE_ACCOUNT private_key is not base64 PEM");
  }
  try {
    return await crypto.subtle.importKey(
      "pkcs8",
      der.buffer as ArrayBuffer,
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["sign"],
    );
  } catch (err) {
    throw new FcmConfigError(`FCM_SERVICE_ACCOUNT private_key could not be imported: ${err}`);
  }
}

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64UrlJson(value: unknown): string {
  return base64Url(new TextEncoder().encode(JSON.stringify(value)));
}

/// Mints (and memoises for the worker's lifetime) an access token via the
/// service-account JWT grant. Cached in module scope on purpose: Supabase
/// keeps an edge worker warm across requests, so a burst of missed-dose
/// alerts costs one token exchange rather than one per notification.
async function getAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (accessToken && accessToken.expiresAt > now + TOKEN_SKEW_SECONDS) {
    return accessToken.value;
  }

  const account = loadServiceAccount();
  const claims = {
    iss: account.client_email,
    scope: SCOPE,
    aud: TOKEN_ENDPOINT,
    iat: now,
    exp: now + 3600,
  };
  const unsigned = `${base64UrlJson({ alg: "RS256", typ: "JWT" })}.${base64UrlJson(claims)}`;
  const key = await importPrivateKey(account.private_key);
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const assertion = `${unsigned}.${base64Url(new Uint8Array(signature))}`;

  const res = await fetch(TOKEN_ENDPOINT, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!res.ok) {
    const text = await res.text().catch(() => "");
    // A rejected assertion is always a configuration fault (wrong key, clock
    // skew, service account deleted) — never a transient one worth retrying.
    throw new FcmConfigError(`token_exchange_${res.status}: ${text.slice(0, 300)}`);
  }
  const payload = await res.json();
  const token = payload.access_token as string | undefined;
  if (!token) throw new FcmConfigError("token exchange returned no access_token");
  accessToken = { value: token, expiresAt: now + ((payload.expires_in as number) ?? 3600) };
  return token;
}

/// Sends [message] to one token.
///
/// A `notification` block is what lets Android draw the alert with the app
/// terminated — the point of the whole exercise. Data-only messages instead
/// need `priority: "high"` or Doze may sit on them for hours, which for a
/// schedule change means the parent's alarms stay wrong overnight.
export async function sendToToken(token: string, message: FcmMessage): Promise<SendResult> {
  const accessTokenValue = await getAccessToken();
  const projectId = fcmProjectId();

  const body: Record<string, unknown> = {
    message: {
      token,
      ...(message.notification ? { notification: message.notification } : {}),
      ...(message.data ? { data: message.data } : {}),
      android: {
        priority: "high",
        ...(message.notification
          ? {
            notification: {
              // A care alert is not an alarm and must not land in the alarm
              // channel: that channel loops its sound until dismissed, which
              // is right for "take your tablet" and hostile for "your mother
              // missed one".
              channel_id: message.androidChannelId,
              default_sound: true,
            },
          }
          : {}),
      },
      // No `apns` block: iOS is not started (see PLAN.md). When it is, a
      // data-only message will need `content-available: 1` and the
      // background-refresh entitlement, neither of which has an Android
      // equivalent to copy.
    },
  };

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), SEND_TIMEOUT_MS);
  let res: Response;
  try {
    res = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
      method: "POST",
      signal: controller.signal,
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${accessTokenValue}`,
      },
      body: JSON.stringify(body),
    });
  } catch (err) {
    return { ok: false, staleToken: false, detail: `send_failed: ${err}` };
  } finally {
    clearTimeout(timer);
  }

  if (res.ok) return { ok: true };

  const text = await res.text().catch(() => "");
  if (res.status === 401 || res.status === 403) {
    throw new FcmConfigError(`fcm_auth_${res.status}: ${text.slice(0, 300)}`);
  }
  return {
    ok: false,
    staleToken: isStale(res.status, text),
    detail: `fcm_${res.status}: ${text.slice(0, 300)}`,
  };
}

/// Whether FCM is telling us this token is dead rather than that the send
/// failed. Both of FCM's ways of saying it are checked:
///
///   * 404 UNREGISTERED — the app was uninstalled, or its data cleared, or
///     the token was reissued and this is the old one.
///   * 400 naming the token — not a well-formed registration token for this
///     project, which also covers a token belonging to a *different* Firebase
///     project (the classic symptom of swapping google-services.json).
///
/// Anything else — 429, 500, 503, a timeout — is transient, and deleting a
/// perfectly good token because Google had a bad minute would silence a
/// family's alerts permanently.
///
/// Note what is deliberately *not* here: a bare `INVALID_ARGUMENT` check. FCM
/// returns that status for a malformed message too — a field we got wrong — and
/// treating it as a verdict on the token would mean one bad payload wiping every
/// device row the app knows about, in a single sweep, for every family. So a 400
/// only counts when the body names the token as the offending part.
export function isStale(status: number, body: string): boolean {
  if (status === 404) return true;
  if (status !== 400) return false;
  return body.includes("registration token") || body.includes("message.token");
}
