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
      const labels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
      // Same reason: labels[9] is a RangeError, not a missing label.
      final days = schedulableDays(schedule.daysOfWeek).map((d) => labels[d]).join(', ');
      return '$days at ${schedule.times.join(', ')}';
    case FrequencyType.everyXHours:
      return 'Every ${schedule.intervalHours ?? '?'} hours';
    case FrequencyType.asNeeded:
      return 'As needed';
  }
}

String medicineTitle(Medicine medicine) =>
    medicine.strength.isEmpty ? medicine.drugName : '${medicine.drugName} ${medicine.strength}';
