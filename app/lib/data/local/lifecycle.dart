import 'database.dart';
import 'tables.dart';

ReminderStatus? reminderStatusFromName(String? value) {
  if (value == null) return null;
  for (final status in ReminderStatus.values) {
    if (status.name == value) return status;
  }
  return null;
}

/// Interprets both Phase-3 rows and legacy rows. A legacy inactive schedule
/// is treated as completed because it has already been stopped and must not
/// silently begin firing after an upgrade.
ReminderStatus reminderStatus(Schedule schedule, {DateTime? now}) {
  final stored = reminderStatusFromName(schedule.status);
  if (stored != null) {
    // `asNeeded` is also the lifecycle value used by older rows to represent
    // the as-needed frequency. It is not a valid lifecycle state for a
    // scheduled frequency. Repair the interpretation here so a malformed
    // row cannot silently disappear from the calendar after an edit or an
    // interrupted migration.
    if (stored == ReminderStatus.asNeeded &&
        schedule.frequencyType != FrequencyType.asNeeded.name) {
      return schedule.active ? ReminderStatus.active : ReminderStatus.completed;
    }
    if (stored == ReminderStatus.paused &&
        schedule.pauseUntil != null &&
        !(schedule.pauseUntil!.isAfter(now ?? DateTime.now()))) {
      return ReminderStatus.active;
    }
    return stored;
  }
  if (schedule.frequencyType == FrequencyType.asNeeded.name) {
    return ReminderStatus.asNeeded;
  }
  return schedule.active ? ReminderStatus.active : ReminderStatus.completed;
}

bool reminderIsActive(Schedule schedule, {DateTime? at}) {
  final instant = at ?? DateTime.now();
  if (reminderStatus(schedule, now: instant) != ReminderStatus.active) {
    return false;
  }
  if (schedule.startDate != null && instant.isBefore(schedule.startDate!)) {
    return false;
  }
  if (schedule.endDate != null && !instant.isBefore(schedule.endDate!)) {
    return false;
  }
  // A paused reminder with an elapsed pause window resumes automatically on
  // the next reconciliation. The legacy boolean remains false until that
  // reconciliation persists the resumed row, so do not let it suppress the
  // due slots in the meantime.
  if (schedule.active) return true;
  return schedule.status == ReminderStatus.paused.name &&
      schedule.pauseUntil != null &&
      !schedule.pauseUntil!.isAfter(instant);
}
