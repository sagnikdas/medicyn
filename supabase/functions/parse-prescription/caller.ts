// Who is calling, established against the auth server rather than inferred.
//
// `verify_jwt = true` in config.toml is not the control it looks like. It
// checks that the request carries a credential the project accepts — and the
// publishable key is one. That key ships inside the app by design and is
// extractable from any APK, so the gateway check alone let anyone holding it
// run unlimited billed model calls on the project owner's Anthropic account,
// with no sign-up and no account of any kind. Verified against the deployed
// function: no credentials returned 401, the publishable key alone returned
// 200 and a full extraction.
//
// So this asks the auth server who the bearer token belongs to, and refuses
// anything that does not resolve to a real user. It is the same reasoning as
// `notify-care`, which validates the caller rather than trusting the gateway;
// it uses a plain fetch instead of supabase-js because identity is all this
// function needs and it has no other reason to carry the SDK.

export type CallerResult =
  | { ok: true; userId: string }
  | { ok: false; error: string; status: number };

const DEFAULT_TIMEOUT_MS = 5_000;

/**
 * Resolves the caller of a request to a user id, or explains why it could not.
 *
 * Fails closed in every direction, including when the auth server cannot be
 * reached: the thing being protected is a billed upstream call, so an
 * unverifiable caller must not get one. An unreachable auth server is
 * reported as 503 rather than 401 so a legitimate client can tell "try again"
 * apart from "sign in again".
 */
export async function verifyCaller(
  authHeader: string | null,
  opts: {
    supabaseUrl: string;
    serviceRoleKey: string;
    fetchImpl?: typeof fetch;
    timeoutMs?: number;
  },
): Promise<CallerResult> {
  const jwt = (authHeader ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!jwt) return { ok: false, error: "not_authenticated", status: 401 };

  const doFetch = opts.fetchImpl ?? fetch;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), opts.timeoutMs ?? DEFAULT_TIMEOUT_MS);

  let res: Response;
  try {
    res = await doFetch(`${opts.supabaseUrl}/auth/v1/user`, {
      method: "GET",
      headers: {
        Authorization: `Bearer ${jwt}`,
        apikey: opts.serviceRoleKey,
      },
      signal: controller.signal,
    });
  } catch {
    return { ok: false, error: "auth_unavailable", status: 503 };
  } finally {
    clearTimeout(timer);
  }

  // The publishable key lands here: it is a credential the project accepts,
  // but it names no user, so /auth/v1/user rejects it.
  if (res.status === 401 || res.status === 403) {
    return { ok: false, error: "not_authenticated", status: 401 };
  }
  if (!res.ok) return { ok: false, error: "auth_unavailable", status: 503 };

  let user: { id?: unknown };
  try {
    user = await res.json();
  } catch {
    return { ok: false, error: "auth_unavailable", status: 503 };
  }

  // A 200 carrying no id is not a user. Treat it as a refusal rather than
  // reading an empty string as an identity.
  if (typeof user.id !== "string" || user.id.length === 0) {
    return { ok: false, error: "not_authenticated", status: 401 };
  }

  return { ok: true, userId: user.id };
}
