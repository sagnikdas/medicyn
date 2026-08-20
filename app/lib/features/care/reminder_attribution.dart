import '../../data/local/database.dart';

/// The newer of a medicine and its schedule, which is what "who changed this"
/// should quote. They are saved together with one timestamp in the review
/// form, but a pull or a partial upsert can still leave them a moment apart.
({String? updatedBy, DateTime updatedAt}) latestReminderChange(
  Medicine medicine,
  Schedule schedule,
) {
  if (schedule.updatedAt.isAfter(medicine.updatedAt)) {
    return (updatedBy: schedule.updatedBy, updatedAt: schedule.updatedAt);
  }
  return (updatedBy: medicine.updatedBy, updatedAt: medicine.updatedAt);
}

/// "Changed by Priya, Tuesday", or null when the last writer was the person
/// the reminder belongs to — their own edits are the default, not news.
///
/// Shown on both phones. [actorDisplayName] is looked up by the caller; a
/// missing name becomes "a family member" rather than an opaque id.
String? reminderChangedByLine({
  required String ownerUserId,
  required String? updatedBy,
  required DateTime updatedAt,
  required String? actorDisplayName,
}) {
  if (updatedBy == null || updatedBy.isEmpty) return null;
  if (updatedBy == ownerUserId) return null;
  final who = actorDisplayName?.trim();
  final name = (who == null || who.isEmpty) ? 'a family member' : who;
  return 'Changed by $name, ${_weekdayName(updatedAt.toLocal())}';
}

String _weekdayName(DateTime local) {
  const names = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  return names[local.weekday - 1];
}
