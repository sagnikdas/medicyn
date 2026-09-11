/// The every-X-hours lattice, shared by the alarm scheduler and missed-dose
/// detection.
///
/// Daily reminders name a clock time, so their past is reconstructible from
/// the calendar. Every-X-hours does not, unless both paths use one origin
/// and one step. The previous alarm path re-anchored to *today's* clock each
/// reconcile, so for an interval that does not divide 24 the slots armed
/// yesterday were not the ones a fresh computation would name today — and
/// reporting those as missed would tell a family their parent skipped a
/// dose that was never asked for.
///
/// Origin is the first parseable dose time on the calendar day the current
/// timing definition started (`timingDefinedAt` — the subset of `updatedAt`
/// that only moves for an edit that actually changes when an alarm fires;
/// see [Schedules.timingDefinedAt]). From there the sequence is
/// `origin + k * intervalHours` forever. [MissedDoseDetector.wasArmed] still
/// drops anything at or before `timingDefinedAt`, so a reminder saved at
/// 15:32 with an 08:00 origin does not invent a 13:00 miss for that same
/// afternoon.
library;

/// Occurrences in `[from, to)` (or `(from, to)` when [includeFrom] is false).
///
/// [intervalHours] must be ≥ 1; anything else returns nothing rather than
/// looping. Capped at [maxOccurrences] so a pathological window cannot
/// spend a foreground walking a century of hourly slots.
List<DateTime> intervalDoseSequence({
  required DateTime origin,
  required int intervalHours,
  required DateTime from,
  required DateTime to,
  int maxOccurrences = 200,
  bool includeFrom = true,
}) {
  if (intervalHours < 1) return const [];
  if (!to.isAfter(from)) return const [];
  if (maxOccurrences <= 0) return const [];

  final step = Duration(hours: intervalHours);
  var cursor = origin;

  if (cursor.isBefore(from) || (!includeFrom && !cursor.isAfter(from))) {
    final delta = from.difference(origin);
    final stepSeconds = intervalHours * 3600;
    var steps = delta.inSeconds <= 0 ? 0 : (delta.inSeconds / stepSeconds).ceil();
    cursor = origin.add(Duration(seconds: steps * stepSeconds));
    var guard = 0;
    while (cursor.isBefore(from) && guard++ < 8) {
      cursor = cursor.add(step);
    }
    if (!includeFrom) {
      while (!cursor.isAfter(from) && guard++ < 16) {
        cursor = cursor.add(step);
      }
    }
  }

  if (includeFrom) {
    if (cursor.isBefore(from)) return const [];
  } else if (!cursor.isAfter(from)) {
    return const [];
  }

  final out = <DateTime>[];
  while (cursor.isBefore(to) && out.length < maxOccurrences) {
    final inWindow = includeFrom ? !cursor.isBefore(from) : cursor.isAfter(from);
    if (inWindow) out.add(cursor);
    cursor = cursor.add(step);
  }
  return out;
}
