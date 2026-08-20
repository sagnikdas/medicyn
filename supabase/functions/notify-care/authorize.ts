// Who may raise which notify-care event. Extracted so the branches the
// audit found untested — patient-only missed_dose, either party on
// data_changed, no active link, unknown event, missing bearer — can be
// asserted without standing up FCM or a database.

export interface CareLinkRef {
  id: string;
  patient_id: string;
  caregiver_id: string | null;
}

export type NotifyEvent = "missed_dose" | "data_changed";

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
  if (event !== "missed_dose" && event !== "data_changed") {
    return { allow: false, status: 400, body: { error: "unknown_event" } };
  }
  const link = opts.link;
  if (!link) {
    return { allow: false, status: 200, body: { sent: 0, reason: "no_active_link" } };
  }
  if (event === "missed_dose" && link.patient_id !== opts.callerId) {
    return { allow: false, status: 200, body: { sent: 0, reason: "caller_is_not_the_patient" } };
  }
  if (event === "data_changed") {
    const onLink = opts.callerId === link.patient_id || opts.callerId === link.caregiver_id;
    if (!onLink || !link.caregiver_id) {
      return { allow: false, status: 200, body: { sent: 0, reason: "caller_not_on_link" } };
    }
  }
  return { allow: true, event, link };
}
