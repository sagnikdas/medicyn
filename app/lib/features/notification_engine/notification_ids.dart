/// Deterministic, stable notification IDs derived from a schedule id + a
/// slot key (a time-of-day like "08:00", or an occurrence index for
/// every-X-hours schedules). Same inputs always produce the same id, so
/// re-scheduling on reconciliation naturally overwrites the right alarm
/// instead of piling up duplicates.
int notificationIdFor(String scheduleId, String slotKey) {
  final combined = '$scheduleId|$slotKey';
  var hash = 0x811c9dc5; // FNV-1a 32-bit offset basis
  for (final codeUnit in combined.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0x7fffffff; // keep positive, fits Android's int id
  }
  return hash == 0 ? 1 : hash;
}

/// The `timeLabel` a snooze one-off carries. Not an `HH:mm`, deliberately:
/// it marks the notification as the re-reminder rather than a slot in the
/// recurring series, which is how [NotificationService.reconcile] knows to
/// leave it armed.
const String snoozeTimeLabel = 'snooze';

/// The id of the single snooze re-reminder for one dose.
///
/// Keyed on the occurrence, so pressing Snooze again replaces the alarm
/// instead of adding one. Cannot collide with the recurring series: those
/// slot keys are `HH:mm`, `<day>-HH:mm`, `slot-N` or `due-HH:mm`, none of
/// which start with `snooze@`.
int snoozeNotificationId(String scheduleId, DateTime scheduledAt) =>
    notificationIdFor(
      scheduleId,
      'snooze@${scheduledAt.toUtc().toIso8601String()}',
    );

