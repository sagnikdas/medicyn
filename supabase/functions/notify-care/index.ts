// Tells the other side of a care link that something happened.
//
// Two events, in opposite directions, and they are not variations on one
// theme — they exist for different reasons:
//
//   * `missed_dose`  — the parent's device swept its own reminders, found a
//     dose nobody answered, and pushed the log. The caregiver gets a visible
//     notification. This is the alert the whole care link is for.
//
//   * `data_changed` — either side edited the parent's medicines or
//     schedules. The *other* device gets a *silent* data message. On the
//     parent's phone that means pull and re-arm; on the caregiver's it means
//     refresh the remote list and attribution. There is still no notification
//     block — PLAN.md's open question about what the parent is told is still
//     open, and a lock-screen banner would also fight 4.3d.
//
//   * `refill_low`   — the parent's device decremented a tracked bottle
//     past the five-day mark. The caregiver gets a visible ping that names
//     no medicine.
//   * `device_silent` — a scheduled job, not a device, because the whole
//     point is that the patient's app did not run. Gated by `CRON_SECRET`.
//
// Why the *device* calls missed_dose / data_changed / refill_low rather than
// a Postgres trigger firing on the insert: a trigger needs `pg_net`, which
// Supabase installs in the `extensions` schema that every security-definer
// function here deliberately excludes from its search_path, plus a service
// key stored in the database. Silent-device is the exception that *must* be
// server-side: the patient's app is not running.
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
const CARE_ALERT_CHANNEL_ID = "medicyn_care_alerts_v1";

// Bound on one call, matched to `MissedDoseDetector._maxPerSweep` on the client
// — the most a single device-side sweep can produce. Deliberately not a smaller
// "sensible" number: a lower cap would silently drop the rest, and the count is
// the whole signal. Forty missed doses means the phone was off for two days, and
// a caregiver should be told forty, not twenty.
const MAX_DOSES_PER_CALL = 200;

// Marks an alert row as "a retry has claimed this and is sending right now",
// so a second concurrent retry's conditional update (WHERE delivered_count =
// 0) can no longer match it. Always resolved back to the real delivered
// count — 0 included — before the request returns; see announceMissedDoses.
const RETRY_IN_FLIGHT = -1;

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
  const cronSecret = Deno.env.get("CRON_SECRET");
  const cronHeader = req.headers.get("x-cron-secret");
  const isCron = Boolean(cronSecret) && cronHeader === cronSecret;

  // Validated against the auth server rather than by decoding `sub` out of the
  // JWT. The gateway's `verify_jwt` already checks the signature, but this
  // function's whole job is to ring a *specific other person's* phone, so it
  // does not want its idea of who is calling to depend on a config flag
  // elsewhere staying set.
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  if (isCron) {
    try {
      return await announceSilentDevices(admin);
    } catch (err) {
      if (err instanceof FcmConfigError) {
        console.error(`fcm_config_error: ${err.message}`);
        return json({ error: "push_not_configured" }, 500);
      }
      console.error(`notify_failed: ${err}`);
      return json({ error: "notify_failed" }, 500);
    }
  }

  if (!jwt) return json({ error: "not_authenticated" }, 401);
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
    if (authz.event === "refill_low") {
      return await announceRefillLow(admin, caller.id, authz.link);
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

  // Ids the upsert above left alone already have a row — either genuinely
  // announced, or a previous attempt that claimed the dose but never reached
  // the caregiver (delivered_count still 0, the send having failed or found
  // no registered token). The client re-offers the same window on every
  // foreground specifically so this can retry those: a conditional update,
  // matched on delivered_count = 0, is what keeps a concurrent retry of the
  // same dose from claiming it twice — once one caller's update flips that
  // column away from 0, the other's WHERE clause no longer matches.
  const firstClaimIds = new Set((claimed ?? []).map((row) => row.dose_log_id as string));
  const retryCandidates = ids.filter((id) => !firstClaimIds.has(id));
  let retriedIds: string[] = [];
  if (retryCandidates.length > 0) {
    const { data: reclaimed, error: reclaimError } = await admin
      .from("care_alerts")
      .update({ delivered_count: RETRY_IN_FLIGHT })
      .eq("link_id", link.id)
      .in("dose_log_id", retryCandidates)
      .eq("delivered_count", 0)
      .select("dose_log_id");
    if (reclaimError) {
      console.error(`care_alerts_reclaim_failed: ${reclaimError.message}`);
    } else {
      retriedIds = (reclaimed ?? []).map((row) => row.dose_log_id as string);
    }
  }

  const newIds = [...firstClaimIds, ...retriedIds];
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
    // the same forged ids until something sticks. Retried rows go back to 0
    // rather than staying at the in-flight sentinel — nothing was sent, so a
    // later, legitimate retry must still be able to claim them.
    if (retriedIds.length > 0) {
      await admin
        .from("care_alerts")
        .update({ delivered_count: 0 })
        .eq("link_id", link.id)
        .in("dose_log_id", retriedIds)
        .eq("delivered_count", RETRY_IN_FLIGHT);
    }
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

  // In a finally so a row retried into RETRY_IN_FLIGHT above is always
  // resolved back to a real count — 0 included — even if deliver() itself
  // throws (a token-exchange failure, say), rather than being left stuck at
  // the sentinel forever.
  let delivered = 0;
  try {
    delivered = await deliver(admin, tokens, message);
  } finally {
    await admin
      .from("care_alerts")
      .update({ delivered_count: delivered })
      .in("dose_log_id", newIds)
      .eq("link_id", link.id);
  }

  return json({ sent: doses.length, recipients: tokens.length, delivered });
}

/// The silent one. Either side of an active link may raise it; the other
/// person is the recipient. A change the parent made still needs to reach
/// the caregiver's open list, and a change the caregiver made still needs to
/// re-arm the parent's alarms.
async function announceDataChange(
  admin: SupabaseClient,
  callerId: string,
  link: CareLinkRow,
): Promise<Response> {
  const recipientId = callerId === link.patient_id ? link.caregiver_id : link.patient_id;
  if (!recipientId) {
    return json({ sent: 0, reason: "no_alarms_to_rearm" });
  }
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

/// The caregiver-facing "the bottle is running out" ping. Copy names no
/// medicine: a lock-screen banner that quoted a drug would recreate the
/// care-alert exposure. De-duplicated to one ping per link per UTC day.
async function announceRefillLow(
  admin: SupabaseClient,
  callerId: string,
  link: CareLinkRow,
): Promise<Response> {
  if (link.patient_id !== callerId) {
    return json({ sent: 0, reason: "caller_is_not_the_patient" });
  }
  const recipientId = link.caregiver_id;
  if (!recipientId) return json({ sent: 0, reason: "no_caregiver" });

  const { data: claimed, error: claimError } = await admin
    .from("care_alerts")
    .insert({
      link_id: link.id,
      recipient_id: recipientId,
      kind: "refill_low",
    })
    .select("id");
  let claimedId: string | null = null;
  if (claimError) {
    // Unique index on (link, UTC day) — already told them today, or a
    // previous attempt claimed today's ping and never got through. Only the
    // second is worth another try; reclaimTodayIfUnsent tells them apart.
    if (claimError.code !== "23505") {
      console.error(`care_alerts_claim_failed: ${claimError.message}`);
      return json({ error: "claim_failed" }, 500);
    }
    claimedId = await reclaimTodayIfUnsent(admin, link.id, "refill_low");
  } else if (claimed && claimed.length > 0) {
    claimedId = claimed[0].id as string;
  }
  if (claimedId === null) {
    return json({ sent: 0, reason: "already_announced" });
  }

  const [patient, tokens] = await Promise.all([
    profileOf(admin, link.patient_id),
    tokensOf(admin, recipientId),
  ]);
  const who = patient.displayName ?? "Someone you help";
  // In a finally so a row reclaimed into RETRY_IN_FLIGHT above is always
  // resolved back to a real count, even if deliver() itself throws.
  let delivered = 0;
  try {
    delivered = await deliver(admin, tokens, {
      notification: {
        title: `${who}'s medicine is running low`,
        body: "Open Medicyn to see which one. About five days of tablets left.",
      },
      androidChannelId: CARE_ALERT_CHANNEL_ID,
      data: {
        event: "refill_low",
        patientId: link.patient_id,
      },
    });
  } finally {
    await admin.from("care_alerts").update({ delivered_count: delivered }).eq("id", claimedId);
  }
  return json({ sent: 1, recipients: tokens.length, delivered });
}

/// Re-claims today's alert of [kind] on [linkId] for a retry, but only if a
/// previous attempt claimed it and never sent anything (delivered_count
/// still 0). The conditional update is the lock: two concurrent retries can
/// only ever have one of them still match a row still at 0.
async function reclaimTodayIfUnsent(
  admin: SupabaseClient,
  linkId: string,
  kind: string,
): Promise<string | null> {
  const { start, end } = utcDayBounds();
  const { data, error } = await admin
    .from("care_alerts")
    .update({ delivered_count: RETRY_IN_FLIGHT })
    .eq("link_id", linkId)
    .eq("kind", kind)
    .gte("sent_at", start)
    .lt("sent_at", end)
    .eq("delivered_count", 0)
    .select("id");
  if (error) {
    console.error(`care_alerts_reclaim_failed: ${error.message}`);
    return null;
  }
  return data && data.length > 0 ? (data[0].id as string) : null;
}

function utcDayBounds(): { start: string; end: string } {
  const now = new Date();
  const start = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
  const end = new Date(start.getTime() + 24 * 60 * 60 * 1000);
  return { start: start.toISOString(), end: end.toISOString() };
}

/// Server-side: the patient's app is not running, so it cannot tell anyone.
/// Invoked with `x-cron-secret`, not a user JWT.
async function announceSilentDevices(admin: SupabaseClient): Promise<Response> {
  const { data: due, error } = await admin.rpc("silent_devices_due");
  if (error) {
    console.error(`silent_devices_due_failed: ${error.message}`);
    return json({ error: "lookup_failed" }, 500);
  }
  const rows = (due ?? []) as Array<{
    link_id: string;
    patient_id: string;
    caregiver_id: string;
    last_seen_at: string | null;
  }>;
  let sent = 0;
  let deliveredTotal = 0;
  for (const row of rows) {
    const { data: claimed, error: claimError } = await admin
      .from("care_alerts")
      .insert({
        link_id: row.link_id,
        recipient_id: row.caregiver_id,
        kind: "device_silent",
      })
      .select("id");
    let claimedId: string | null = null;
    if (claimError) {
      // 20260824120000_retry_unsent_device_silent.sql only excludes a link
      // from `due` once its alert actually delivered, so a 23505 here means
      // a previous attempt claimed today's row and never got through.
      if (claimError.code !== "23505") {
        console.error(`care_alerts_claim_failed: ${claimError.message}`);
        continue;
      }
      claimedId = await reclaimTodayIfUnsent(admin, row.link_id, "device_silent");
    } else if (claimed && claimed.length > 0) {
      claimedId = claimed[0].id as string;
    }
    if (claimedId === null) continue;

    const [patient, tokens] = await Promise.all([
      profileOf(admin, row.patient_id),
      tokensOf(admin, row.caregiver_id),
    ]);
    const who = patient.displayName ?? "Someone you help";
    // In a finally so a row reclaimed into RETRY_IN_FLIGHT above is always
    // resolved back to a real count, even if deliver() itself throws.
    let delivered = 0;
    try {
      delivered = await deliver(admin, tokens, {
        notification: {
          title: `${who}'s phone hasn't checked in`,
          body: "It hasn't opened Medicyn since yesterday. This is not a missed dose — their app did not run.",
        },
        androidChannelId: CARE_ALERT_CHANNEL_ID,
        data: {
          event: "device_silent",
          patientId: row.patient_id,
        },
      });
    } finally {
      await admin.from("care_alerts").update({ delivered_count: delivered }).eq("id", claimedId);
    }
    sent += 1;
    deliveredTotal += delivered;
  }
  return json({ sent, delivered: deliveredTotal });
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
