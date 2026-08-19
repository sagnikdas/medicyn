// Tells the other side of a care link that something happened.
//
// Two events, in opposite directions, and they are not variations on one
// theme — they exist for different reasons:
//
//   * `missed_dose`  — the parent's device swept its own reminders, found a
//     dose nobody answered, and pushed the log. The caregiver gets a visible
//     notification. This is the alert the whole care link is for.
//
//   * `data_changed` — the caregiver edited the parent's medicines or
//     schedules. The parent's device gets a *silent* data message, pulls, and
//     re-arms its alarms. Without it a schedule change sits unapplied until
//     the parent next opens the app, while the caregiver believes it is live.
//
// Why the *device* calls this rather than a Postgres trigger firing on the
// insert: a trigger needs `pg_net`, which Supabase installs in the
// `extensions` schema that every security-definer function here deliberately
// excludes from its search_path, plus a service key stored in the database.
// It would buy nothing today either — missed doses are only ever produced by
// the parent's own device (see MissedDoseDetector), so there is no second
// writer for a trigger to catch.
//
// Notification *content* is read from the database here, never taken from the
// request. The client sends dose-log ids and nothing else, so what a family is
// told cannot be composed by a caller.

import { createClient, SupabaseClient } from "@supabase/supabase-js";

import { authorizeNotify, bearerToken, CareLinkRef } from "./authorize.ts";
import { FcmConfigError, FcmMessage, sendToToken } from "./fcm.ts";

// Must match `careAlertChannelId` in
// app/lib/features/notification_engine/notification_service.dart. The client
// creates the channel; Android silently drops a notification addressed to a
// channel id that does not exist.
const CARE_ALERT_CHANNEL_ID = "dosely_care_alerts_v1";

// Bound on one call, matched to `MissedDoseDetector._maxPerSweep` on the client
// — the most a single device-side sweep can produce. Deliberately not a smaller
// "sensible" number: a lower cap would silently drop the rest, and the count is
// the whole signal. Forty missed doses means the phone was off for two days, and
// a caregiver should be told forty, not twenty.
const MAX_DOSES_PER_CALL = 200;

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

interface NotifyRequest {
  event?: string;
  doseLogIds?: unknown;
}

type CareLinkRow = CareLinkRef;

interface MissedDoseRow {
  id: string;
  scheduled_at: string;
  schedules: { medicines: { drug_name: string; strength: string | null } };
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
    console.error("SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY missing from the function environment");
    return json({ error: "server_misconfigured" }, 500);
  }

  const jwt = bearerToken(req.headers.get("Authorization"));
  if (!jwt) return json({ error: "not_authenticated" }, 401);

  // Validated against the auth server rather than by decoding `sub` out of the
  // JWT. The gateway's `verify_jwt` already checks the signature, but this
  // function's whole job is to ring a *specific other person's* phone, so it
  // does not want its idea of who is calling to depend on a config flag
  // elsewhere staying set.
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await admin.auth.getUser(jwt);
  const caller = userData?.user;
  if (userError || !caller) return json({ error: "not_authenticated" }, 401);

  let body: NotifyRequest;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json_body" }, 400);
  }

  const { data: linkRows, error: linkError } = await admin
    .from("care_links")
    .select("id, patient_id, caregiver_id")
    .eq("status", "active")
    .or(`patient_id.eq.${caller.id},caregiver_id.eq.${caller.id}`)
    .limit(1);
  if (linkError) {
    console.error(`care_links_read_failed: ${linkError.message}`);
    return json({ error: "lookup_failed" }, 500);
  }
  const authz = authorizeNotify({
    event: body.event,
    callerId: caller.id,
    link: linkRows?.[0] as CareLinkRow | undefined,
  });
  if (!authz.allow) return json(authz.body, authz.status);

  try {
    if (authz.event === "missed_dose") {
      return await announceMissedDoses(admin, caller.id, authz.link, body.doseLogIds);
    }
    return await announceDataChange(admin, caller.id, authz.link);
  } catch (err) {
    if (err instanceof FcmConfigError) {
      // Ours to fix, and invisible to the user either way — the app treats any
      // failure here as "the notification did not go out", which is true.
      console.error(`fcm_config_error: ${err.message}`);
      return json({ error: "push_not_configured" }, 500);
    }
    console.error(`notify_failed: ${err}`);
    return json({ error: "notify_failed" }, 500);
  }
});

/// The caregiver-facing alert. Only the patient of a link can raise it: the
/// dose is theirs, and the caregiver has nothing to report about themselves.
async function announceMissedDoses(
  admin: SupabaseClient,
  callerId: string,
  link: CareLinkRow,
  rawIds: unknown,
): Promise<Response> {
  if (link.patient_id !== callerId) {
    return json({ sent: 0, reason: "caller_is_not_the_patient" });
  }
  const recipientId = link.caregiver_id;
  if (!recipientId) return json({ sent: 0, reason: "no_caregiver" });

  const ids = Array.isArray(rawIds)
    ? rawIds.filter((v): v is string => typeof v === "string").slice(0, MAX_DOSES_PER_CALL)
    : [];
  if (ids.length === 0) return json({ sent: 0, reason: "no_doses" });

  // Claim the doses first, then send. Inserting before sending is what makes
  // the unique index the lock: two devices signed into the same account push
  // the same deterministically-id'd missed dose, and whichever loses this
  // insert sends nothing rather than ringing the caregiver's phone twice.
  const { data: claimed, error: claimError } = await admin
    .from("care_alerts")
    .upsert(
      ids.map((id) => ({
        link_id: link.id,
        recipient_id: recipientId,
        kind: "missed_dose",
        dose_log_id: id,
      })),
      { onConflict: "link_id,dose_log_id", ignoreDuplicates: true },
    )
    .select("id, dose_log_id");
  if (claimError) {
    console.error(`care_alerts_claim_failed: ${claimError.message}`);
    return json({ error: "claim_failed" }, 500);
  }
  const newIds = (claimed ?? []).map((row) => row.dose_log_id as string);
  if (newIds.length === 0) return json({ sent: 0, reason: "already_announced" });

  // Read the doses back rather than trusting the request for what to say. The
  // `user_id`/`action` filters are load-bearing: without them a caller could
  // name any dose-log id and have this compose a notification about it.
  const { data: doseRows, error: doseError } = await admin
    .from("dose_logs")
    .select("id, scheduled_at, schedules!inner(medicines!inner(drug_name, strength))")
    .in("id", newIds)
    .eq("user_id", callerId)
    .eq("action", "missed")
    .order("scheduled_at", { ascending: false });
  if (doseError) {
    console.error(`dose_logs_read_failed: ${doseError.message}`);
    return json({ error: "lookup_failed" }, 500);
  }
  const doses = (doseRows ?? []) as unknown as MissedDoseRow[];
  if (doses.length === 0) {
    // The ids did not name missed doses of the caller's. The claim rows stay:
    // they cost nothing, and removing them would reopen the door to retrying
    // the same forged ids until something sticks.
    return json({ sent: 0, reason: "no_matching_doses" });
  }

  const [patient, tokens] = await Promise.all([
    profileOf(admin, link.patient_id),
    tokensOf(admin, recipientId),
  ]);

  const latest = doses[0];
  const medicine = describeMedicine(latest);
  const dueAt = formatTime(latest.scheduled_at, patient.timezone);
  const who = patient.displayName ?? "Someone you help";

  const message: FcmMessage = {
    notification: {
      title: doses.length === 1
        ? `${who} missed a dose`
        : `${who} missed ${doses.length} doses`,
      // Deliberately "not marked as taken", not "did not take". The app knows
      // that nobody answered the reminder; it does not know what happened.
      body: doses.length === 1
        ? `${medicine} was due at ${dueAt} and is not marked as taken.`
        : `${medicine} at ${dueAt}, and ${doses.length - 1} other ${
          doses.length === 2 ? "dose" : "doses"
        }, are not marked as taken.`,
    },
    androidChannelId: CARE_ALERT_CHANNEL_ID,
    data: {
      event: "missed_dose",
      patientId: link.patient_id,
      doseCount: String(doses.length),
    },
  };

  const delivered = await deliver(admin, tokens, message);
  await admin
    .from("care_alerts")
    .update({ delivered_count: delivered })
    .in("dose_log_id", newIds)
    .eq("link_id", link.id);

  return json({ sent: doses.length, recipients: tokens.length, delivered });
}

/// The silent one. Only the caregiver can raise it, because the parent's device
/// is the only one with alarms to re-arm — a change the parent made on their own
/// phone is already applied there, and the caregiver's feed reads live from
/// Postgres. Phase 2 widens this to carry attribution both ways.
async function announceDataChange(
  admin: SupabaseClient,
  callerId: string,
  link: CareLinkRow,
): Promise<Response> {
  if (link.caregiver_id !== callerId) {
    return json({ sent: 0, reason: "no_alarms_to_rearm" });
  }
  const recipientId = link.patient_id;
  const tokens = await tokensOf(admin, recipientId);

  // No `notification` block: the parent should not be told "your daughter
  // changed something" by a system notification they cannot act on. The app
  // pulls and re-arms; PLAN.md's open question about what the parent is told
  // is deliberately still open.
  const delivered = await deliver(admin, tokens, {
    data: { event: "data_changed", changedBy: callerId },
  });

  const { error } = await admin.from("care_alerts").insert({
    link_id: link.id,
    recipient_id: recipientId,
    kind: "data_changed",
    delivered_count: delivered,
  });
  if (error) console.error(`care_alerts_insert_failed: ${error.message}`);

  return json({ sent: 1, recipients: tokens.length, delivered });
}

/// Sends to every one of the recipient's devices and drops the tokens FCM says
/// are dead. Returns how many accepted it — zero is the number worth watching:
/// it means the recipient's phone cannot be reached at all.
async function deliver(
  admin: SupabaseClient,
  tokens: string[],
  message: FcmMessage,
): Promise<number> {
  if (tokens.length === 0) return 0;
  // In parallel because a person has one or two phones, not hundreds, and
  // FCM v1 has no multicast endpoint to batch them into.
  const results = await Promise.all(tokens.map((token) => sendToToken(token, message)));

  const stale: string[] = [];
  for (const [i, result] of results.entries()) {
    if (result.ok) continue;
    console.error(`push_failed: ${result.detail}`);
    if (result.staleToken) stale.push(tokens[i]);
  }
  if (stale.length > 0) {
    const { error } = await admin.from("device_tokens").delete().in("token", stale);
    if (error) console.error(`stale_token_delete_failed: ${error.message}`);
  }
  return results.filter((r) => r.ok).length;
}

async function tokensOf(admin: SupabaseClient, userId: string): Promise<string[]> {
  const { data, error } = await admin
    .from("device_tokens")
    .select("token")
    .eq("user_id", userId);
  if (error) {
    console.error(`device_tokens_read_failed: ${error.message}`);
    return [];
  }
  return (data ?? []).map((row) => row.token as string);
}

async function profileOf(
  admin: SupabaseClient,
  userId: string,
): Promise<{ displayName: string | null; timezone: string | null }> {
  const { data } = await admin
    .from("profiles")
    .select("display_name, timezone")
    .eq("user_id", userId)
    .limit(1);
  const row = data?.[0];
  return {
    displayName: (row?.display_name as string | null) ?? null,
    timezone: (row?.timezone as string | null) ?? null,
  };
}

function describeMedicine(dose: MissedDoseRow): string {
  const medicine = dose.schedules?.medicines;
  const name = medicine?.drug_name?.trim() || "A medicine";
  const strength = medicine?.strength?.trim();
  return strength ? `${name} ${strength}` : name;
}

/// The due time, rendered in the *patient's* timezone — the clock time that
/// actually appeared on their phone. A caregiver in another city being shown
/// "09:00" when the reminder said 09:00 is the point; converting it to their
/// own zone would name a time nobody ever saw. Matches DoseFeedScreen.
function formatTime(iso: string, timezone: string | null): string {
  try {
    return new Intl.DateTimeFormat("en-GB", {
      hour: "2-digit",
      minute: "2-digit",
      timeZone: timezone ?? "UTC",
    }).format(new Date(iso));
  } catch {
    // An unrecognised IANA name (an old profile, a device that lied) must not
    // cost the whole notification.
    return new Intl.DateTimeFormat("en-GB", { hour: "2-digit", minute: "2-digit" })
      .format(new Date(iso));
  }
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}
