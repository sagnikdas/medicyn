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

/// Sent by the *caregiver's* device after it has pushed an edit to the
/// patient's medicines or schedules. The patient's device receives it silently,
/// pulls, and re-arms its alarms.
///
/// This is the direction that is easy to forget and expensive to omit: without
/// it a schedule the caregiver changed does not reach the parent's alarms until
/// they next open the app, while the caregiver believes the change is live.
const String pushEventDataChanged = 'data_changed';

/// The key every message's `data` map carries, naming which of the above it is.
const String pushEventKey = 'event';

/// Whose record a `missed_dose` notification is about, so tapping it can open
/// the right feed.
const String pushPatientIdKey = 'patientId';
