import '../reminders_home/day_occurrences.dart' show calendarDay;
import 'parsed_care_item.dart';

/// Expands one [ParsedCareItem]'s recurrence hint into concrete calendar
/// dates -- [ParsedCareItem.occurrenceCount] entries starting at
/// [ParsedCareItem.firstDate] (or [now]'s own day, if the model gave no
/// usable date), stepped per [ParsedCareItem.recurrence]. This is where the
/// "generate individual reminders now" decision is actually implemented:
/// each returned date becomes one ordinary, independently editable
/// [TodayCareReminder] row at review time -- there is no recurring-series
/// concept anywhere in the schema.
///
/// Pure and total: every input, however malformed, produces a bounded,
/// non-empty list of dates. [ParsedCareItem.fromJson] already bounds
/// [ParsedCareItem.occurrenceCount] to 1-52 and [ParsedCareItem.intervalN]
/// to 1-365, but this re-clamps rather than trusting that -- the same
/// defense-in-depth reasoning as re-validating the edge function's output
/// on the client at all.
List<DateTime> expandCareOccurrences(ParsedCareItem item, {DateTime? now}) {
  final start = item.firstDate != null
      ? calendarDay(item.firstDate!)
      : calendarDay(now ?? DateTime.now());
  final interval = item.intervalN.clamp(1, 365);
  // "none" always means exactly one date, regardless of what
  // occurrenceCount happens to say -- generating several identical dates
  // for a one-off item would be both wrong and wasteful.
  final count = item.recurrence == CareRecurrence.none
      ? 1
      : item.occurrenceCount.clamp(1, 52);

  return [
    for (var i = 0; i < count; i++)
      switch (item.recurrence) {
        CareRecurrence.none => start,
        CareRecurrence.weekly => start.add(Duration(days: 7 * i)),
        CareRecurrence.everyNDays => start.add(Duration(days: interval * i)),
        CareRecurrence.everyNMonths => _addMonths(start, interval * i),
      },
  ];
}

/// Adds [months] calendar months to [date], clamping the day rather than
/// letting [DateTime]'s own overflow roll into a later month -- e.g. 31 Jan
/// + 1 month lands on 28/29 Feb, not 2/3 Mar.
DateTime _addMonths(DateTime date, int months) {
  final totalMonths = date.month - 1 + months;
  final year = date.year + totalMonths ~/ 12;
  final month = totalMonths % 12 + 1;
  final day = date.day.clamp(1, _daysInMonth(year, month));
  return DateTime(year, month, day);
}

int _daysInMonth(int year, int month) {
  final isLeap =
      (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
  const days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  return month == 2 && isLeap ? 29 : days[month - 1];
}
