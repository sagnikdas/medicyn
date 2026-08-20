// Who may raise which notify-care event. Extracted so the branches the
// audit found untested — patient-only missed_dose, either-side
// data_changed, no active link, unknown event, missing bearer — can be
// asserted without standing up FCM or a database.

export interface CareLinkRef {
  id: string;
  patient_id: string;
  caregiver_id: string | null;
}

export type NotifyEvent = "missed_dose" | "data_changed" | "refill_low";

export type NotifyAuthz =
  | { allow: true; event: NotifyEvent; link: CareLinkRef }
  | { allow: false; status: number; body: Record<string, unknown> };

/// Empty, missing, or whitespace-only Authorization is not a caller.
export function bearerToken(authorizationHeader: string | null): string | null {
  const jwt = (authorizationHeader ?? "").replace(/^Bearer\s+/i, "").trim();
  return jwt.length === 0 ? null : jwt;
}

/// Decides whether [callerId] may fire [event] on the active [link] the
/// handler already loaded. A missing link is success-with-zero: the app
/// calls this unconditionally and the server is the one that knows.
export function authorizeNotify(opts: {
  event: unknown;
  callerId: string;
  link: CareLinkRef | null | undefined;
}): NotifyAuthz {
  const event = opts.event;
  if (event !== "missed_dose" && event !== "data_changed" && event !== "refill_low") {
    return { allow: false, status: 400, body: { error: "unknown_event" } };
  }
  const link = opts.link;
  if (!link) {
    return { allow: false, status: 200, body: { sent: 0, reason: "no_active_link" } };
  }
  if ((event === "missed_dose" || event === "refill_low") && link.patient_id !== opts.callerId) {
    return { allow: false, status: 200, body: { sent: 0, reason: "caller_is_not_the_patient" } };
  }
  if (event === "data_changed") {
    const isPatient = link.patient_id === opts.callerId;
    const isCaregiver = link.caregiver_id === opts.callerId;
    // Either side may tell the other. A claimed (unconfirmed) link has no
    // caregiver yet, so there is nobody to notify — same quiet zero as
    // before, not an error, because the app calls this after every save.
    if (!isPatient && !isCaregiver) {
      return { allow: false, status: 200, body: { sent: 0, reason: "no_alarms_to_rearm" } };
    }
    if (!link.caregiver_id) {
      return { allow: false, status: 200, body: { sent: 0, reason: "no_alarms_to_rearm" } };
    }
  }
  return { allow: true, event, link };
}
