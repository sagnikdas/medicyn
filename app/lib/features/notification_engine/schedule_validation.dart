/// Guards for the values the alarm scheduler loops over.
///
/// Everything here is a pure function that takes an untrusted value and
/// returns either something safe to schedule or nothing at all. Nothing in
/// this file throws.
///
/// ## Why the scheduler needs its own guards
///
/// A schedule's `times`, `daysOfWeek` and `intervalHours` reach the device
/// from three places, and none of them validates: the model's tool output via
/// the review screen, the review screen's own text fields, and a pull from
/// Supabase — which a linked caregiver can write. The scheduler used them
/// directly as loop bounds, so a `daysOfWeek` of `9` (no `DateTime.weekday`
/// ever equals it) or an `intervalHours` of `0` (an increment that never
/// advances) produced a loop that could not terminate.
///
/// That is worse than it sounds, because [NotificationService.reconcile]
/// cancels every alarm on the device *before* re-arming them. A single
/// unschedulable row therefore took every other medicine's alarms down with
/// it, silently, and stayed that way across restarts. For a medicine
/// reminder, no alarm is the worst available outcome.
///
/// Validating at the three entry points is the real fix and is tracked
/// separately. These guards exist so that a value which gets past them still
/// cannot cost the user their other reminders — a scheduler that arms alarms
/// from stored data should not be able to hang on any input, whatever wrote
/// it.
library;

import '../../data/local/tables.dart';

/// A wall-clock time of day, already range-checked.
typedef ClockTime = ({int hour, int minute});

/// Thrown when a stored schedule cannot be armed at all.
///
/// Deliberately an exception rather than a silent return: skipping one
/// schedule is a decision worth surfacing, since the user is expecting an
/// alarm they will not get. [NotificationService.reconcile] catches it,
/// records the id, and carries on with the rest.
class UnschedulableSchedule implements Exception {
  const UnschedulableSchedule(this.scheduleId, this.reason);

  final String scheduleId;
  final String reason;

  @override
  String toString() => 'UnschedulableSchedule($scheduleId): $reason';
}

/// Parses `HH:mm`, returning null rather than throwing on anything else.
///
/// The old code did `int.parse(parts[0])` and `parts[1]` straight off a
/// `split(':')`, so `"9am"` threw a `FormatException` and a string with no
/// colon threw a `RangeError`. Both aborted the caller mid-reconcile, after
/// the cancel sweep had already run.
///
/// A single-digit hour (`"9:05"`) is accepted because it names an unambiguous
/// time; an out-of-range one (`"29:00"`) is not, because `DateTime` would
/// silently roll it over into the next day and arm the alarm at a time the
/// user never chose.
ClockTime? parseClockTime(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length != 2) return null;

  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;

  // int.tryParse accepts a leading sign; a negative time is not a time.
  if (parts[0].startsWith('-') || parts[1].startsWith('-')) return null;
  if (hour < 0 || hour > 23) return null;
  if (minute < 0 || minute > 59) return null;

  return (hour: hour, minute: minute);
}

/// A stored time string that parsed, paired with the time it names.
///
/// The original [label] is carried through because it is what forms the
/// notification id and payload — recomputing it from [clock] would change
/// the id of every already-armed alarm.
typedef SchedulableTime = ({String label, ClockTime clock});

/// The subset of [times] that names a real time of day, in the original
/// order and without duplicates.
///
/// Duplicates are dropped because each time becomes part of a notification
/// id; two identical entries would arm one alarm and quietly discard the
/// other, which looks like a scheduling bug rather than a data one.
List<SchedulableTime> schedulableTimes(List<String> times) {
  final seen = <String>{};
  final out = <SchedulableTime>[];
  for (final time in times) {
    final clock = parseClockTime(time);
    if (clock == null) continue;
    if (!seen.add(time)) continue;
    out.add((label: time, clock: clock));
  }
  return out;
}

/// The subset of [days] that names a real day of the week, sorted and
/// deduplicated.
///
/// The stored convention is 0 = Sunday through 6 = Saturday, which the
/// scheduler maps onto `DateTime.weekday`'s 1 = Monday through 7 = Sunday.
/// Anything outside 0..6 has no counterpart to map to, and the review screen
/// cannot show it either — it renders exactly seven chips, so an out-of-range
/// day is invisible there and cannot be deselected by the user.
List<int> schedulableDays(List<int> days) {
  final valid = days.where((d) => d >= 0 && d <= 6).toSet().toList()..sort();
  return valid;
}

/// The interval to use for an every-X-hours schedule, or null if the stored
/// value cannot be scheduled.
///
/// Null [intervalHours] means the field was never set, and keeps the
/// long-standing 8-hour default. A value outside 1..24 is different: someone
/// entered or synced it, and guessing a replacement would arm alarms at times
/// nobody asked for. Better to leave that one schedule unarmed and visibly
/// broken than to invent a dosing interval for it.
int? schedulableIntervalHours(int? intervalHours, {int fallback = 8}) {
  if (intervalHours == null) return fallback;
  if (intervalHours < 1 || intervalHours > 24) return null;
  return intervalHours;
}

/// The frequency named by [raw], or null if it names none of them.
///
/// `FrequencyType.values.byName` throws on an unrecognised string, and
/// `frequencyType` arrives from the same unvalidated sources as everything
/// else here — including a pull from Supabase, which a linked caregiver can
/// write. Callers that are storing a row want the null; callers that are
/// reading one they already stored can treat null as impossible.
FrequencyType? frequencyTypeFromName(String? raw) {
  if (raw == null) return null;
  for (final candidate in FrequencyType.values) {
    if (candidate.name == raw) return candidate;
  }
  return null;
}

/// A schedule's fields, cleaned so that nothing downstream has to re-check
/// them, and nothing unschedulable is ever written to the database.
typedef ScheduleFields = ({
  FrequencyType frequency,
  List<String> times,
  List<int> daysOfWeek,
  int? intervalHours,
  bool changed,
});

/// Cleans one schedule's fields, or returns null if the row cannot be stored
/// as a working schedule at all.
///
/// The guards in this file exist so the scheduler cannot be hung by a stored
/// value. This function is the other half: it stops such a value being stored
/// in the first place, at each of the three boundaries that write one — the
/// model's tool output, the review form, and a pull from Supabase.
///
/// Salvage is preferred over rejection, because a schedule the user is
/// expecting is worth keeping if any of it is usable. Two cases cannot be
/// salvaged and return null instead:
///
///   - a `frequencyType` naming nothing, since there is no way to guess what
///     the row meant;
///   - an out-of-range `intervalHours`, since substituting a default would
///     arm alarms at times nobody chose.
///
/// [changed] reports whether anything was dropped, so a caller can tell the
/// user that what it stored is not quite what it was given.
ScheduleFields? sanitiseScheduleFields({
  required String? frequencyType,
  required List<String> times,
  required List<int> daysOfWeek,
  required int? intervalHours,
}) {
  final frequency = frequencyTypeFromName(frequencyType);
  if (frequency == null) return null;

  final cleanTimes = schedulableTimes(times).map((t) => t.label).toList();
  final cleanDays = schedulableDays(daysOfWeek);

  // Only meaningful for every-X-hours; for any other frequency the column is
  // ignored, so an odd value there is not worth rejecting a row over.
  int? cleanInterval = intervalHours;
  if (frequency == FrequencyType.everyXHours) {
    if (schedulableIntervalHours(intervalHours) == null) return null;
  } else {
    cleanInterval = intervalHours;
  }

  final changed = cleanTimes.length != times.length || cleanDays.length != daysOfWeek.length;

  return (
    frequency: frequency,
    times: cleanTimes,
    daysOfWeek: cleanDays,
    intervalHours: cleanInterval,
    changed: changed,
  );
}
