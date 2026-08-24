import '../../data/local/database.dart';
import '../../data/local/tables.dart';
import '../notification_engine/schedule_validation.dart';

/// Warn when the bottle would run out in this many days, not when a single
/// tablet remains. Five days is long enough to get to a pharmacy; a
/// last-tablet warning arrives after it could have helped.
const int refillWarnDays = 5;

/// How many answered doses this schedule consumes in an average 24 hours.
///
/// As-needed schedules contribute nothing: there is no honest daily rate,
/// and inventing one would cry empty on a bottle that is being used slowly.
double dailyDoseCount(Schedule schedule) {
  if (!schedule.active) return 0;
  final frequency = frequencyTypeFromName(schedule.frequencyType);
  if (frequency == null) return 0;
  switch (frequency) {
    case FrequencyType.daily:
      return schedulableTimes(schedule.times).length.toDouble();
    case FrequencyType.specificDays:
      final days = schedulableDays(schedule.daysOfWeek);
      final times = schedulableTimes(schedule.times);
      if (days.isEmpty || times.isEmpty) return 0;
      return times.length * days.length / 7.0;
    case FrequencyType.everyXHours:
      final interval = schedulableIntervalHours(schedule.intervalHours);
      if (interval == null) return 0;
      return 24 / interval;
    case FrequencyType.asNeeded:
      return 0;
  }
}

/// Whole days the remaining tablets last at [schedules]' combined rate.
///
/// Null when the user is not tracking this bottle, or when every schedule
/// is as-needed so there is no rate to divide by. Zero means the bottle is
/// empty *or* would not last the rest of today.
int? refillDaysLeft({
  required int? tabletsRemaining,
  required int? tabletsPerDose,
  required List<Schedule> schedules,
}) {
  if (tabletsRemaining == null) return null;
  if (tabletsRemaining <= 0) return 0;
  final perDose = (tabletsPerDose == null || tabletsPerDose < 1) ? 1 : tabletsPerDose;
  var daily = 0.0;
  for (final schedule in schedules) {
    daily += dailyDoseCount(schedule);
  }
  if (daily <= 0) return null;
  return (tabletsRemaining / perDose / daily).floor();
}

bool refillIsLow(int? daysLeft) => daysLeft != null && daysLeft <= refillWarnDays;

/// The bottle's count right now: the last explicitly-entered baseline minus
/// what has been taken since.
///
/// [medicine.tabletsRemaining] only changes when a save — this device's or a
/// linked caregiver's — writes a new number; nothing decrements it in place.
/// [takenSinceBaseline] must count only doses logged strictly after
/// [medicine.updatedAt], the moment that baseline was captured, since every
/// save re-stamps both fields together from the derived count shown at save
/// time. Counting from any earlier point would subtract a dose that was
/// already folded into the baseline.
int? derivedTabletsRemaining(Medicine medicine, int takenSinceBaseline) {
  final baseline = medicine.tabletsRemaining;
  if (baseline == null) return null;
  final perDose = (medicine.tabletsPerDose == null || medicine.tabletsPerDose! < 1)
      ? 1
      : medicine.tabletsPerDose!;
  final remaining = baseline - perDose * takenSinceBaseline;
  return remaining < 0 ? 0 : remaining;
}

/// True when any tracked bottle on [items] is at or below the warning.
///
/// [takenSinceBaseline] is doses taken since each medicine's baseline was
/// set, keyed by medicine id — see [derivedTabletsRemaining]. A medicine
/// missing from the map is treated as having none, which is right for a
/// baseline just set with nothing taken against it yet.
bool anyRefillLow(
  List<ScheduleWithMedicine> items,
  Map<String, int> takenSinceBaseline,
) {
  final remaining = <String, Medicine>{};
  final byMedicine = <String, List<Schedule>>{};
  for (final item in items) {
    remaining[item.medicine.id] = item.medicine;
    byMedicine.putIfAbsent(item.medicine.id, () => []).add(item.schedule);
  }
  for (final id in remaining.keys) {
    final medicine = remaining[id]!;
    if (refillIsLow(refillDaysLeft(
      tabletsRemaining: derivedTabletsRemaining(medicine, takenSinceBaseline[id] ?? 0),
      tabletsPerDose: medicine.tabletsPerDose,
      schedules: byMedicine[id]!,
    ))) {
      return true;
    }
  }
  return false;
}

/// Short line for a card. Null when tracking is off or the bottle is fine.
String? refillWarningLine(int? daysLeft) {
  if (!refillIsLow(daysLeft)) return null;
  if (daysLeft == 0) return 'No tablets left';
  if (daysLeft == 1) return 'About 1 day of tablets left';
  return 'About $daysLeft days of tablets left';
}
