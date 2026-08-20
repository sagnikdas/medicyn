// Whether a data_changed call should wake the parent's alarms or ping the
// caregiver. Extracted so the two deliveries can be asserted without FCM.

import { CareLinkRef } from "./authorize.ts";

export const DATA_CHANGED_TITLE = "A reminder was changed";
export const DATA_CHANGED_BODY = "Open Dosely to see what changed.";

export type DataChangePlan =
  | { send: false; reason: string }
  | { send: true; recipientId: string; silent: boolean };

export function planDataChange(callerId: string, link: CareLinkRef): DataChangePlan {
  if (callerId === link.caregiver_id) {
    return { send: true, recipientId: link.patient_id, silent: true };
  }
  if (callerId === link.patient_id && link.caregiver_id) {
    return { send: true, recipientId: link.caregiver_id, silent: false };
  }
  return { send: false, reason: "caller_not_on_link" };
}
