/// The wire contract between this app and the `notify-care` edge function.
///
/// Kept in one file, in both languages, because it is the kind of agreement
/// that breaks silently: a renamed event string produces no error anywhere —
/// the function sends a push the device receives and ignores, and the family
/// simply never hears about a missed dose. The matching constants live in
/// `supabase/functions/notify-care/index.ts`.
library;

/// Sent by the *patient's* device after it has pushed dose logs it recorded as
/// missed. The caregiver gets a visible notification.
const String pushEventMissedDose = 'missed_dose';

/// Sent after either side of a care link has pushed an edit to medicines or
/// schedules.
///
/// Two deliveries, distinguished by [pushRearmKey]:
///
///  * Caregiver → parent: silent, `rearm=true`. The parent's device pulls and
///    re-arms its alarms.
///  * Parent → caregiver: visible, `rearm=false`. The caregiver is told a
///    reminder changed, with no medicine name. Their device must **not** pull:
///    the local encrypted file is a different person's medicines.
const String pushEventDataChanged = 'data_changed';

/// The key every message's `data` map carries, naming which of the above it is.
const String pushEventKey = 'event';

/// Whose record a care notification is about, so tapping it can open the
/// right screen.
const String pushPatientIdKey = 'patientId';

/// On a [pushEventDataChanged] message: `"true"` means pull and re-arm,
/// `"false"` means a visible ping only.
const String pushRearmKey = 'rearm';
const String pushRearmYes = 'true';
const String pushRearmNo = 'false';

/// Whether this payload should write into *this* device's local database.
///
/// A visible ping is for the caregiver. Pulling it would mix the patient's
/// medicines into the caregiver's encrypted file. Legacy silent messages
/// (no `rearm` key, no notification block) still pull — that was the only
/// shape Phase 1 sent.
bool shouldPullAndRearm({
  required String? event,
  required String? rearm,
  required bool hasNotification,
}) {
  if (event != pushEventDataChanged) return false;
  if (hasNotification) return false;
  if (rearm == pushRearmNo) return false;
  return true;
}
