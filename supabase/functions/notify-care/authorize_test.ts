import { assertEquals } from "@std/assert";

import { authorizeNotify, bearerToken } from "./authorize.ts";

const link = {
  id: "link-1",
  patient_id: "patient-1",
  caregiver_id: "caregiver-1",
};

Deno.test("a missing Authorization header is not a caller", () => {
  assertEquals(bearerToken(null), null);
  assertEquals(bearerToken(""), null);
  assertEquals(bearerToken("Bearer "), null);
  assertEquals(bearerToken("Bearer    "), null);
});

Deno.test("a Bearer token is returned trimmed", () => {
  assertEquals(bearerToken("Bearer user-jwt"), "user-jwt");
  assertEquals(bearerToken("user-jwt"), "user-jwt");
});

Deno.test("an unknown event is refused before the link is consulted", () => {
  const result = authorizeNotify({ event: "forged_alert", callerId: "patient-1", link });
  assertEquals(result, { allow: false, status: 400, body: { error: "unknown_event" } });
});

Deno.test("no active link is a quiet zero, not an error", () => {
  const result = authorizeNotify({ event: "missed_dose", callerId: "patient-1", link: null });
  assertEquals(result, {
    allow: false,
    status: 200,
    body: { sent: 0, reason: "no_active_link" },
  });
});

Deno.test("missed_dose is only the patient's to raise", () => {
  const asPatient = authorizeNotify({ event: "missed_dose", callerId: "patient-1", link });
  assertEquals(asPatient, { allow: true, event: "missed_dose", link });

  const asCaregiver = authorizeNotify({ event: "missed_dose", callerId: "caregiver-1", link });
  assertEquals(asCaregiver, {
    allow: false,
    status: 200,
    body: { sent: 0, reason: "caller_is_not_the_patient" },
  });

  const asStranger = authorizeNotify({ event: "missed_dose", callerId: "stranger", link });
  assertEquals(asStranger, {
    allow: false,
    status: 200,
    body: { sent: 0, reason: "caller_is_not_the_patient" },
  });
});

Deno.test("data_changed is either side of an active link", () => {
  const asCaregiver = authorizeNotify({ event: "data_changed", callerId: "caregiver-1", link });
  assertEquals(asCaregiver, { allow: true, event: "data_changed", link });

  const asPatient = authorizeNotify({ event: "data_changed", callerId: "patient-1", link });
  assertEquals(asPatient, { allow: true, event: "data_changed", link });

  const asStranger = authorizeNotify({ event: "data_changed", callerId: "stranger", link });
  assertEquals(asStranger, {
    allow: false,
    status: 200,
    body: { sent: 0, reason: "no_alarms_to_rearm" },
  });
});

Deno.test("a claimed link with no caregiver cannot raise data_changed", () => {
  const claimed = { ...link, caregiver_id: null };
  const result = authorizeNotify({
    event: "data_changed",
    callerId: "patient-1",
    link: claimed,
  });
  assertEquals(result, {
    allow: false,
    status: 200,
    body: { sent: 0, reason: "no_alarms_to_rearm" },
  });
});

Deno.test("refill_low is only the patient's to raise", () => {
  const asPatient = authorizeNotify({ event: "refill_low", callerId: "patient-1", link });
  assertEquals(asPatient, { allow: true, event: "refill_low", link });

  const asCaregiver = authorizeNotify({ event: "refill_low", callerId: "caregiver-1", link });
  assertEquals(asCaregiver, {
    allow: false,
    status: 200,
    body: { sent: 0, reason: "caller_is_not_the_patient" },
  });
});
