import '../../data/local/database.dart';
import '../../data/local/tables.dart';
import 'interval_dose_sequence.dart';
import 'schedule_validation.dart';

/// When a schedule *should* have gone off, over a window of the recent past.
///
/// Separate from the code that arms alarms because the two questions differ:
/// arming asks "what is next", this asks "what already was". Keeping it a
/// pure function over local wall-clock time also makes it testable, which
/// matters more here than usual — a wrong answer marks a dose missed that
/// never was, and tells a family in another city that their parent skipped
/// their medication.
///
/// Every-X-hours shares [intervalDoseSequence] with the alarm scheduler,
/// originating at the first parseable time on the calendar day the current
/// definition started (`updatedAt`). As-needed still yields nothing: there
/// is nothing to miss.
List<DateTime> expectedDoses(
  Schedule schedule, {
  required DateTime from,
  required DateTime to,
}) {
  if (!schedule.active || schedule.times.isEmpty) return const [];

  // A row stored before these fields were validated can still be here, and a
  // throw would abort the whole missed-dose sweep rather than skip one
  // schedule — which would silently stop a family being told about any of
  // them.
  final frequency = frequencyTypeFromName(schedule.frequencyType);
  if (frequency == null) return const [];
  switch (frequency) {
    case FrequencyType.daily:
      return _atClockTimes(schedule.times, from: from, to: to);
    case FrequencyType.specificDays:
      if (schedule.daysOfWeek.isEmpty) return const [];
      return _atClockTimes(
        schedule.times,
        from: from,
        to: to,
        onDays: schedule.daysOfWeek.toSet(),
      );
    case FrequencyType.everyXHours:
      final interval = schedulableIntervalHours(schedule.intervalHours);
      if (interval == null) return const [];
      final times = schedulableTimes(schedule.times);
      if (times.isEmpty) return const [];
      final defined = schedule.updatedAt;
      final clock = times.first.clock;
      final origin = DateTime(
        defined.year,
        defined.month,
        defined.day,
        clock.hour,
        clock.minute,
      );
      return intervalDoseSequence(
        origin: origin,
        intervalHours: interval,
        from: from,
        to: to,
      );
    case FrequencyType.asNeeded:
      return const [];
  }
}

/// Every occurrence of the given "HH:mm" times falling inside the window,
/// optionally restricted to certain weekdays (0 = Sunday, matching the rest
/// of the app and the `days_of_week` column).
List<DateTime> _atClockTimes(
  List<String> times, {
  required DateTime from,
  required DateTime to,
  Set<int>? onDays,
}) {
  if (!to.isAfter(from)) return const [];

  final occurrences = <DateTime>[];
  // Start from the calendar day `from` falls in, so a time earlier that same
  // day is still considered before being filtered by the window below.
  var day = DateTime(from.year, from.month, from.day);
  final lastDay = DateTime(to.year, to.month, to.day);

  while (!day.isAfter(lastDay)) {
    // Dart's weekday runs Monday=1..Sunday=7; the app stores Sunday=0.
    final storedWeekday = day.weekday == DateTime.sunday ? 0 : day.weekday;
    if (onDays == null || onDays.contains(storedWeekday)) {
      for (final time in times) {
        final at = _onDayAt(day, time);
        if (at == null) continue;
        // Half-open: an occurrence exactly at `to` has not happened yet.
        if (at.isBefore(from) || !at.isBefore(to)) continue;
        occurrences.add(at);
      }
    }
    day = DateTime(day.year, day.month, day.day + 1);
  }

  occurrences.sort();
  return occurrences;
}

/// Parses "HH:mm" onto [day]. Returns null for anything malformed rather
/// than throwing — one unparseable time should cost that one occurrence, not
/// the whole sweep.
DateTime? _onDayAt(DateTime day, String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length != 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  // Constructing through the local-time constructor means a day that has no
  // such wall-clock time — the hour a DST jump skips — lands on the
  // neighbouring instant rather than failing.
  return DateTime(day.year, day.month, day.day, hour, minute);
}
