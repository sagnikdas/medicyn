import '../../core/locale_dates.dart';
import '../../data/local/database.dart';
import '../../data/local/tables.dart';
import '../notification_engine/schedule_validation.dart';

/// The subtitle on a reminder card. Shared by the home list and the
/// caregiver's remote list so the two cannot drift.
String describeSchedule(Schedule schedule) {
  // A row stored before these fields were validated can still be here, and
  // this runs for every card in the list — so an unrecognised frequency
  // would blank the whole screen rather than one row.
  final frequency = frequencyTypeFromName(schedule.frequencyType);
  if (frequency == null) return 'Schedule needs attention';
  switch (frequency) {
    case FrequencyType.daily:
      return 'Daily at ${schedule.times.join(', ')}';
    case FrequencyType.specificDays:
      // Same reason as before: an out-of-range day is a RangeError, not a
      // missing label -- schedulableDays already only yields 0-6.
      final days = schedulableDays(
        schedule.daysOfWeek,
      ).map(localeShortWeekdayForSundayIndex).join(', ');
      return '$days at ${schedule.times.join(', ')}';
    case FrequencyType.everyXHours:
      return 'Every ${schedule.intervalHours ?? '?'} hours';
    case FrequencyType.asNeeded:
      return 'As needed';
  }
}

String medicineTitle(Medicine medicine) =>
    medicine.strength.isEmpty ? medicine.drugName : '${medicine.drugName} ${medicine.strength}';
