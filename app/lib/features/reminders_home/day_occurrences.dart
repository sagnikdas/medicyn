import 'package:timezone/timezone.dart' as tz;

import '../../data/local/database.dart';
import '../../data/local/tables.dart';
import '../../data/local/lifecycle.dart';
import '../notification_engine/expected_doses.dart';
import '../notification_engine/missed_doses.dart';

/// How a scheduled dose looks on the home calendar.
///
/// Distinct from [DoseAction] because the calendar has to paint silence —
/// a dose that was due and never answered — without inventing a missed
/// row. [DayDoseStatus.missed] is only used when a missed log already
/// exists; [notRecorded] is the honest past-tense of "nobody answered".
enum DayDoseStatus { taken, pending, upcoming, snoozed, missed, notRecorded }

/// A dose log the calendar can reason about. Unknown [DoseLog.action]
/// values are dropped rather than guessed — a string the enum does not
/// know is not a status we can paint.
class DoseRecord {
  const DoseRecord({
    required this.scheduleId,
    required this.scheduledAt,
    required this.loggedAt,
    required this.action,
  });

  final String scheduleId;
  final DateTime scheduledAt;
  final DateTime loggedAt;
  final DoseAction action;

  static DoseRecord? tryFromLog(DoseLog log) {
    final action = _actionByName(log.action);
    if (action == null) return null;
    return DoseRecord(
      scheduleId: log.scheduleId,
      scheduledAt: log.scheduledAt,
      loggedAt: log.loggedAt,
      action: action,
    );
  }
}

/// [DoseRecord]s bucketed by schedule and calendar day, built once and
/// reused for every day a range walk visits.
///
/// The grouping this replaces lived inside [occurrencesOnDay], so a
/// two-year calendar rebuilt it 730 times and then had [_winningLog] scan
/// the whole of a schedule's history for every dose slot on every one of
/// those days — quadratic in history, and paid on each rebuild, including
/// the ones the home screen's minute timer fires.
///
/// A log is filed under its `scheduledAt` day *and* its `loggedAt` day,
/// because [_winningLog] matches on either one. [forDay] then reads a
/// small window of days around the one asked for, so a slot at midnight
/// still sees the log 60 seconds the other side of it, and a caregiver
/// reading the feed in another timezone still sees logs whose civil date
/// there is a day off from the one here.
class DoseRecordIndex {
  DoseRecordIndex(List<DoseRecord> logs) {
    for (final log in logs) {
      final byDay = _byScheduleDay.putIfAbsent(log.scheduleId, () => {});
      final scheduledDay = _dayKey(log.scheduledAt);
      byDay.putIfAbsent(scheduledDay, () => []).add(log);
      final loggedDay = _dayKey(log.loggedAt);
      if (loggedDay != scheduledDay) {
        byDay.putIfAbsent(loggedDay, () => []).add(log);
      }
    }
  }

  /// Two days either side. One would cover the midnight edge; two also
  /// covers the widest pair of timezones, where the same instant carries
  /// civil dates 26 hours apart.
  static const _window = 2;

  final Map<String, Map<int, List<DoseRecord>>> _byScheduleDay = {};

  /// Every log that could belong to a dose slot on [day].
  ///
  /// Deduplicated by identity: a log filed under two different days can be
  /// reached twice by the window. Buckets hold a handful of rows each, so
  /// the linear check is cheaper than allocating a set per call.
  List<DoseRecord> forDay(String scheduleId, DateTime day) {
    final byDay = _byScheduleDay[scheduleId];
    if (byDay == null) return const [];
    final out = <DoseRecord>[];
    for (var offset = -_window; offset <= _window; offset++) {
      final bucket = byDay[_dayKey(_civilAddDays(day, offset))];
      if (bucket == null) continue;
      for (final log in bucket) {
        if (!out.contains(log)) out.add(log);
      }
    }
    return out;
  }
}

/// A civil date as a sortable int, so buckets key off year/month/day rather
/// than a [DateTime] — `TZDateTime` and `DateTime` naming the same date are
/// not interchangeable map keys, and the caregiver feed mixes both.
int _dayKey(DateTime day) => day.year * 10000 + day.month * 100 + day.day;

/// One expected (or historically logged) dose on a calendar day.
class DayOccurrence {
  const DayOccurrence({
    required this.item,
    required this.scheduledAt,
    required this.status,
    this.record,
  });

  final ScheduleWithMedicine item;
  final DateTime scheduledAt;
  final DayDoseStatus status;
  final DoseRecord? record;
}

/// Per-day flags for the month grid. Several statuses can be true at
/// once — a morning taken and an evening still due is the common case.
class DayCellMarks {
  const DayCellMarks({
    this.hasTaken = false,
    this.hasPending = false,
    this.hasUpcoming = false,
    this.hasSnoozed = false,
    this.hasMissed = false,
    this.hasNotRecorded = false,
  });

  final bool hasTaken;
  final bool hasPending;
  final bool hasUpcoming;
  final bool hasSnoozed;
  final bool hasMissed;
  final bool hasNotRecorded;

  bool get isEmpty =>
      !hasTaken &&
      !hasPending &&
      !hasUpcoming &&
      !hasSnoozed &&
      !hasMissed &&
      !hasNotRecorded;
}

DateTime calendarDay(DateTime dt) {
  if (dt is tz.TZDateTime) {
    return tz.TZDateTime(dt.location, dt.year, dt.month, dt.day);
  }
  return DateTime(dt.year, dt.month, dt.day);
}

DateTime _civilAddDays(DateTime day, int days) {
  if (day is tz.TZDateTime) {
    return tz.TZDateTime(day.location, day.year, day.month, day.day + days);
  }
  return DateTime(day.year, day.month, day.day + days);
}

bool isSameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Occurrences that belong on [day], using [now] only to tell pending from
/// upcoming and a live snooze from an expired one.
///
/// [grace] is accepted so callers share knobs with [MissedDoseDetector],
/// but it does not change today's unanswered dose into [notRecorded] —
/// the sweep writes missed, and silence beats a false alarm until it does.
List<DayOccurrence> occurrencesOnDay({
  required List<ScheduleWithMedicine> items,
  List<DoseRecord> logs = const [],
  DoseRecordIndex? index,
  required DateTime day,
  required DateTime now,
  Duration grace = MissedDoseDetector.grace,
  Duration snoozeWindow = const Duration(minutes: 10),
  WallClock? wallClock,
}) {
  assert(!grace.isNegative);
  final today = calendarDay(now);
  final onDay = calendarDay(day);
  final dayEnd = _civilAddDays(onDay, 1);
  final logIndex = index ?? DoseRecordIndex(logs);

  final out = <DayOccurrence>[];
  for (final item in items) {
    final schedule = item.schedule;
    final scheduleLogs = logIndex.forDay(schedule.id, onDay);

    // expectedDoses returns [] for inactive rows, which would hide a taken
    // or missed log from a reminder that was later turned off. History has
    // to stay visible; we just must not invent pending/notRecorded for a
    // schedule that is no longer firing.
    final live =
        reminderIsActive(schedule, at: now) &&
        !schedule.deleted &&
        !item.medicine.deleted;
    if (!live) {
      out.addAll(
        _occurrencesFromLogsOnly(
          item: item,
          logs: scheduleLogs,
          day: onDay,
          now: now,
          snoozeWindow: snoozeWindow,
        ),
      );
      continue;
    }

    final dues =
        expectedDoses(schedule, from: onDay, to: dayEnd, wallClock: wallClock)
            .where(
              (due) => MissedDoseDetector.wasArmed(
                due,
                definedAt: schedule.updatedAt,
              ),
            )
            .toList();
    // A snooze belongs to the reminder definition that was active when the
    // user pressed it. If the schedule was edited afterwards, ignore that
    // old snooze so it cannot hide the newly edited occurrence (the immutable
    // log remains available in History).
    final currentScheduleLogs = scheduleLogs
        .where(
          (log) =>
              log.action != DoseAction.snoozed ||
              !log.loggedAt.isBefore(schedule.updatedAt),
        )
        .toList();
    for (var i = 0; i < dues.length; i++) {
      final due = dues[i];
      final nextDue = i + 1 < dues.length ? dues[i + 1] : dayEnd;
      final record = _winningLog(
        due: due,
        nextDue: nextDue,
        logs: currentScheduleLogs,
        now: now,
        snoozeWindow: snoozeWindow,
      );
      final status = record != null
          ? _statusFromRecord(record, now, snoozeWindow)!
          : _statusWithoutLog(day: onDay, today: today, due: due, now: now);
      out.add(
        DayOccurrence(
          item: item,
          scheduledAt: due,
          status: status,
          record: record,
        ),
      );
    }
  }

  out.sort((a, b) {
    final byTime = a.scheduledAt.compareTo(b.scheduledAt);
    if (byTime != 0) return byTime;
    return a.item.medicine.drugName.compareTo(b.item.medicine.drugName);
  });
  return out;
}

/// [rangeStart] inclusive and [rangeEnd] exclusive, both as calendar dates.
/// Empty days are omitted so a quiet month stays a small map.
Map<DateTime, DayCellMarks> cellMarksForRange({
  required List<ScheduleWithMedicine> items,
  List<DoseRecord> logs = const [],
  DoseRecordIndex? index,
  required DateTime rangeStart,
  required DateTime rangeEnd,
  required DateTime now,
  Duration grace = MissedDoseDetector.grace,
  Duration snoozeWindow = const Duration(minutes: 10),
  WallClock? wallClock,
}) {
  final logIndex = index ?? DoseRecordIndex(logs);
  final marks = <DateTime, DayCellMarks>{};
  var day = calendarDay(rangeStart);
  final end = calendarDay(rangeEnd);
  while (day.isBefore(end)) {
    final occs = occurrencesOnDay(
      items: items,
      index: logIndex,
      day: day,
      now: now,
      grace: grace,
      snoozeWindow: snoozeWindow,
      wallClock: wallClock,
    );
    final cell = _marksFrom(occs);
    if (!cell.isEmpty) marks[day] = cell;
    day = _civilAddDays(day, 1);
  }
  return marks;
}

/// Adherence for the Sunday–Saturday week that contains [now].
///
/// [taken] is every occurrence already marked taken. [expected] is every
/// occurrence that is already due or past — not [upcoming], and not a
/// future day's pending — so a Friday afternoon is not scored against
/// Saturday's doses.
({int taken, int expected}) weekAdherence({
  required List<ScheduleWithMedicine> items,
  List<DoseRecord> logs = const [],
  DoseRecordIndex? index,
  required DateTime now,
  Duration grace = MissedDoseDetector.grace,
  Duration snoozeWindow = const Duration(minutes: 10),
  WallClock? wallClock,
}) {
  final logIndex = index ?? DoseRecordIndex(logs);
  final today = calendarDay(now);
  final storedWeekday = now.weekday == DateTime.sunday ? 0 : now.weekday;
  final sunday = _civilAddDays(today, -storedWeekday);
  final nextSunday = _civilAddDays(sunday, 7);

  var taken = 0;
  var expected = 0;
  var day = sunday;
  while (day.isBefore(nextSunday)) {
    final occs = occurrencesOnDay(
      items: items,
      index: logIndex,
      day: day,
      now: now,
      grace: grace,
      snoozeWindow: snoozeWindow,
      wallClock: wallClock,
    );
    for (final o in occs) {
      if (o.status == DayDoseStatus.taken) taken++;
      if (o.status == DayDoseStatus.upcoming) continue;
      if (calendarDay(o.scheduledAt).isAfter(today)) continue;
      expected++;
    }
    day = _civilAddDays(day, 1);
  }
  return (taken: taken, expected: expected);
}

/// Morning before noon, afternoon until 17:00, evening after that.
/// Used to group Today's schedule the way the Stitch design does.
enum DayPart { morning, afternoon, evening }

DayPart dayPartOf(DateTime scheduledAt) {
  final hour = scheduledAt.toLocal().hour;
  if (hour < 12) return DayPart.morning;
  if (hour < 17) return DayPart.afternoon;
  return DayPart.evening;
}

Map<DayPart, List<DayOccurrence>> groupByDayPart(List<DayOccurrence> occs) {
  final grouped = {for (final part in DayPart.values) part: <DayOccurrence>[]};
  for (final occurrence in occs) {
    grouped[dayPartOf(occurrence.scheduledAt)]!.add(occurrence);
  }
  return grouped;
}

/// The next dose on [occs] the person can still answer — pending, due, or
/// snoozed, earliest first. Taken/missed/unrecorded rows are skipped.
DayOccurrence? nextActionableDose(List<DayOccurrence> occs) {
  final actionable = occs.where((o) {
    switch (o.status) {
      case DayDoseStatus.pending:
      case DayDoseStatus.upcoming:
      case DayDoseStatus.snoozed:
        return true;
      case DayDoseStatus.taken:
      case DayDoseStatus.missed:
      case DayDoseStatus.notRecorded:
        return false;
    }
  }).toList()..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  return actionable.isEmpty ? null : actionable.first;
}

/// Doses to answer by opening the app, so nobody has to hunt the system
/// notification shade while the alarm is still looping.
///
/// Today: due, snoozed, or already written missed. Yesterday: missed or
/// unanswered, so last night is still on the list at breakfast.
List<DayOccurrence> attentionDoses({
  required List<DayOccurrence> today,
  required List<DayOccurrence> yesterday,
}) {
  final out = <DayOccurrence>[];
  for (final o in today) {
    switch (o.status) {
      case DayDoseStatus.pending:
      case DayDoseStatus.snoozed:
      case DayDoseStatus.missed:
        out.add(o);
      case DayDoseStatus.taken:
      case DayDoseStatus.upcoming:
      case DayDoseStatus.notRecorded:
        break;
    }
  }
  for (final o in yesterday) {
    switch (o.status) {
      case DayDoseStatus.missed:
      case DayDoseStatus.notRecorded:
        out.add(o);
      case DayDoseStatus.taken:
      case DayDoseStatus.pending:
      case DayDoseStatus.upcoming:
      case DayDoseStatus.snoozed:
        break;
    }
  }
  return out;
}

/// Upcoming later today — not already on the attention list.
DayOccurrence? nextUpcomingDose(List<DayOccurrence> todayOccs) {
  final upcoming =
      todayOccs.where((o) => o.status == DayDoseStatus.upcoming).toList()
        ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  return upcoming.isEmpty ? null : upcoming.first;
}

bool doseCanSnooze(DayDoseStatus status) {
  switch (status) {
    case DayDoseStatus.pending:
    case DayDoseStatus.snoozed:
      return true;
    case DayDoseStatus.taken:
    case DayDoseStatus.upcoming:
    case DayDoseStatus.missed:
    case DayDoseStatus.notRecorded:
      return false;
  }
}

/// A looping alarm should start again if they leave without answering.
bool doseStillRings(DayDoseStatus status) => doseCanSnooze(status);

DateTime addCalendarDays(DateTime day, int days) =>
    _civilAddDays(calendarDay(day), days);

/// Taken vs expected for each day of the Sunday–Saturday week that
/// contains [now]. Same scoring as [weekAdherence]: upcoming and future
/// days are not in the denominator.
List<({DateTime day, int taken, int expected})> weekDayAdherence({
  required List<ScheduleWithMedicine> items,
  List<DoseRecord> logs = const [],
  DoseRecordIndex? index,
  required DateTime now,
  Duration grace = MissedDoseDetector.grace,
  Duration snoozeWindow = const Duration(minutes: 10),
  WallClock? wallClock,
}) {
  final logIndex = index ?? DoseRecordIndex(logs);
  final today = calendarDay(now);
  final storedWeekday = now.weekday == DateTime.sunday ? 0 : now.weekday;
  final sunday = _civilAddDays(today, -storedWeekday);
  final out = <({DateTime day, int taken, int expected})>[];
  var day = sunday;
  for (var i = 0; i < 7; i++) {
    final occs = occurrencesOnDay(
      items: items,
      index: logIndex,
      day: day,
      now: now,
      grace: grace,
      snoozeWindow: snoozeWindow,
      wallClock: wallClock,
    );
    var taken = 0;
    var expected = 0;
    for (final o in occs) {
      if (o.status == DayDoseStatus.taken) taken++;
      if (o.status == DayDoseStatus.upcoming) continue;
      if (calendarDay(o.scheduledAt).isAfter(today)) continue;
      expected++;
    }
    out.add((day: day, taken: taken, expected: expected));
    day = _civilAddDays(day, 1);
  }
  return out;
}

/// Consecutive calendar days, walking backwards from [now], on which every
/// due dose was taken. Days with nothing expected are skipped rather than
/// counted, so a gap in the schedule does not mint a streak.
int consistencyStreak({
  required List<ScheduleWithMedicine> items,
  List<DoseRecord> logs = const [],
  DoseRecordIndex? index,
  required DateTime now,
  Duration grace = MissedDoseDetector.grace,
  Duration snoozeWindow = const Duration(minutes: 10),
  WallClock? wallClock,
  int maxDays = 365,
}) {
  final logIndex = index ?? DoseRecordIndex(logs);
  var streak = 0;
  var day = calendarDay(now);
  for (var i = 0; i < maxDays; i++) {
    final occs = occurrencesOnDay(
      items: items,
      index: logIndex,
      day: day,
      now: now,
      grace: grace,
      snoozeWindow: snoozeWindow,
      wallClock: wallClock,
    );
    var taken = 0;
    var expected = 0;
    for (final o in occs) {
      if (o.status == DayDoseStatus.taken) taken++;
      if (o.status == DayDoseStatus.upcoming) continue;
      if (calendarDay(o.scheduledAt).isAfter(calendarDay(now))) continue;
      expected++;
    }
    if (expected == 0) {
      day = _civilAddDays(day, -1);
      continue;
    }
    if (taken < expected) break;
    streak++;
    day = _civilAddDays(day, -1);
  }
  return streak;
}

/// Which [DayPart] missed the most doses this week, or null when none did.
DayPart? mostMissedDayPart({
  required List<ScheduleWithMedicine> items,
  List<DoseRecord> logs = const [],
  DoseRecordIndex? index,
  required DateTime now,
  Duration grace = MissedDoseDetector.grace,
  Duration snoozeWindow = const Duration(minutes: 10),
  WallClock? wallClock,
}) {
  final logIndex = index ?? DoseRecordIndex(logs);
  final today = calendarDay(now);
  final storedWeekday = now.weekday == DateTime.sunday ? 0 : now.weekday;
  final sunday = _civilAddDays(today, -storedWeekday);
  final counts = {for (final part in DayPart.values) part: 0};
  var day = sunday;
  for (var i = 0; i < 7; i++) {
    final occs = occurrencesOnDay(
      items: items,
      index: logIndex,
      day: day,
      now: now,
      grace: grace,
      snoozeWindow: snoozeWindow,
      wallClock: wallClock,
    );
    for (final o in occs) {
      if (o.status == DayDoseStatus.missed ||
          o.status == DayDoseStatus.notRecorded) {
        counts[dayPartOf(o.scheduledAt)] =
            counts[dayPartOf(o.scheduledAt)]! + 1;
      }
    }
    day = _civilAddDays(day, 1);
  }
  DayPart? worst;
  var worstCount = 0;
  for (final part in DayPart.values) {
    final n = counts[part]!;
    if (n > worstCount) {
      worst = part;
      worstCount = n;
    }
  }
  return worst;
}

List<DayOccurrence> _occurrencesFromLogsOnly({
  required ScheduleWithMedicine item,
  required List<DoseRecord> logs,
  required DateTime day,
  required DateTime now,
  required Duration snoozeWindow,
}) {
  final out = <DayOccurrence>[];
  for (final log in logs) {
    if (!isSameCalendarDay(log.scheduledAt, day)) continue;
    final status = _statusFromRecord(log, now, snoozeWindow);
    if (status == null) continue;
    out.add(
      DayOccurrence(
        item: item,
        scheduledAt: log.scheduledAt,
        status: status,
        record: log,
      ),
    );
  }
  return out;
}

/// A log belongs to this slot if its own `scheduledAt` names it, or if it
/// landed in the answering window — the latter because notification
/// payloads can carry the wrong date when someone answers late.
DoseRecord? _winningLog({
  required DateTime due,
  required DateTime nextDue,
  required List<DoseRecord> logs,
  required DateTime now,
  required Duration snoozeWindow,
}) {
  final matches = <DoseRecord>[];
  for (final log in logs) {
    final scheduledClose =
        log.scheduledAt.difference(due).abs() <= const Duration(seconds: 60);
    final inWindow =
        !log.loggedAt.isBefore(due) && log.loggedAt.isBefore(nextDue);
    if (!scheduledClose && !inWindow) continue;
    // An expired snooze is not an answer; dropping it here lets a live
    // snooze (or a taken/missed) still win, and leaves no-log rules if
    // nothing else matched.
    if (_statusFromRecord(log, now, snoozeWindow) == null) continue;
    matches.add(log);
  }
  if (matches.isEmpty) return null;
  matches.sort((a, b) => _actionRank(b.action) - _actionRank(a.action));
  return matches.first;
}

int _actionRank(DoseAction action) => switch (action) {
  DoseAction.taken => 2,
  DoseAction.missed => 1,
  DoseAction.snoozed => 0,
};

DayDoseStatus? _statusFromRecord(
  DoseRecord record,
  DateTime now,
  Duration snoozeWindow,
) {
  switch (record.action) {
    case DoseAction.taken:
      return DayDoseStatus.taken;
    case DoseAction.missed:
      return DayDoseStatus.missed;
    case DoseAction.snoozed:
      if (record.loggedAt.add(snoozeWindow).isAfter(now)) {
        return DayDoseStatus.snoozed;
      }
      return null;
  }
}

DayDoseStatus _statusWithoutLog({
  required DateTime day,
  required DateTime today,
  required DateTime due,
  required DateTime now,
}) {
  if (day.isAfter(today)) return DayDoseStatus.pending;
  if (day.isBefore(today)) return DayDoseStatus.notRecorded;
  if (due.isAfter(now)) return DayDoseStatus.upcoming;
  return DayDoseStatus.pending;
}

DayCellMarks _marksFrom(List<DayOccurrence> occs) {
  var hasTaken = false;
  var hasPending = false;
  var hasUpcoming = false;
  var hasSnoozed = false;
  var hasMissed = false;
  var hasNotRecorded = false;
  for (final o in occs) {
    switch (o.status) {
      case DayDoseStatus.taken:
        hasTaken = true;
      case DayDoseStatus.pending:
        hasPending = true;
      case DayDoseStatus.upcoming:
        hasUpcoming = true;
      case DayDoseStatus.snoozed:
        hasSnoozed = true;
      case DayDoseStatus.missed:
        hasMissed = true;
      case DayDoseStatus.notRecorded:
        hasNotRecorded = true;
    }
  }
  return DayCellMarks(
    hasTaken: hasTaken,
    hasPending: hasPending,
    hasUpcoming: hasUpcoming,
    hasSnoozed: hasSnoozed,
    hasMissed: hasMissed,
    hasNotRecorded: hasNotRecorded,
  );
}

DoseAction? _actionByName(String name) {
  for (final value in DoseAction.values) {
    if (value.name == name) return value;
  }
  return null;
}
