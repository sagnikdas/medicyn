// Run with a Deno toolchain (the one `supabase functions serve` uses will do):
//
//   deno test --config supabase/functions/notify-care/deno.json \
//     supabase/functions/notify-care/
//
// Only [isStale] is covered, and deliberately so: it is the one decision in the
// push path that is destructive and irreversible. Every other failure here costs
// a single undelivered notification, which the next sweep or foreground retries.
// Getting this wrong deletes a working token — and a family then hears nothing,
// forever, with the app reporting itself perfectly healthy.

import { assertEquals } from "@std/assert";

import { buildFcmRequestBody, isStale } from "./fcm.ts";

Deno.test("404 UNREGISTERED — the app was uninstalled or its data cleared", () => {
  assertEquals(
    isStale(404, '{"error":{"status":"NOT_FOUND","details":[{"errorCode":"UNREGISTERED"}]}}'),
    true,
  );
});

Deno.test("400 INVALID_ARGUMENT — not a token for this project", () => {
  // The classic symptom of a swapped google-services.json: every token in the
  // table is well-formed and belongs to the wrong Firebase project.
  assertEquals(
    isStale(400, '{"error":{"status":"INVALID_ARGUMENT","message":"The registration token is not a valid FCM registration token"}}'),
    true,
  );
});

Deno.test("429 is Google rate-limiting us, not a dead token", () => {
  assertEquals(isStale(429, '{"error":{"status":"RESOURCE_EXHAUSTED"}}'), false);
});

Deno.test("500 and 503 are FCM having a bad minute", () => {
  // These are the ones that would do real damage if misread: an FCM outage
  // would wipe every device token the app knows about in a single sweep.
  assertEquals(isStale(500, '{"error":{"status":"INTERNAL"}}'), false);
  assertEquals(isStale(503, '{"error":{"status":"UNAVAILABLE"}}'), false);
});

Deno.test("a 400 about something other than the token is not the token's fault", () => {
  // A malformed message — a field we got wrong — must not be blamed on the
  // device it was addressed to.
  assertEquals(
    isStale(400, '{"error":{"status":"INVALID_ARGUMENT","message":"Invalid JSON payload received. Unknown name \\"notifcation\\""}}'),
    false,
  );
});

Deno.test("an empty body on an unrecognised status keeps the token", () => {
  // Silence is not evidence. Anything we cannot read as "this token is dead"
  // leaves the row alone.
  assertEquals(isStale(418, ""), false);
  assertEquals(isStale(400, ""), false);
});

Deno.test("a data-only message gets a silent apns payload, not an alert", () => {
  // The re-arm ping (data_changed) must never surface on the lock screen —
  // it also must not be dropped, which was the bug: with no `apns` block at
  // all, iOS treats a message with no alert/sound/badge as nothing to
  // deliver, silently, with no error anywhere to point at it.
  const body = buildFcmRequestBody("tok", { data: { event: "data_changed" } });
  const message = (body.message as Record<string, unknown>);
  const apns = message.apns as Record<string, unknown>;
  const payload = apns.payload as Record<string, unknown>;
  const aps = payload.aps as Record<string, unknown>;
  assertEquals(aps["content-available"], 1);
  assertEquals("alert" in aps, false);
  assertEquals("sound" in aps, false);
  assertEquals("badge" in aps, false);
  assertEquals(apns.headers, { "apns-priority": "5", "apns-push-type": "background" });
});

Deno.test("a message with a notification block gets an audible apns alert", () => {
  // FCM mirrors `notification` into `aps.alert` on its own; `aps.sound` is
  // the one thing it does not fill in, so a missed-dose alert would arrive
  // silent on iOS without this.
  const body = buildFcmRequestBody("tok", {
    notification: { title: "Missed dose", body: "Your mother missed a dose." },
    androidChannelId: "medicyn_care_alerts_v1",
  });
  const message = (body.message as Record<string, unknown>);
  const apns = message.apns as Record<string, unknown>;
  const payload = apns.payload as Record<string, unknown>;
  const aps = payload.aps as Record<string, unknown>;
  assertEquals(aps.sound, "default");
  assertEquals("content-available" in aps, false);
  assertEquals(apns.headers, undefined);
});
