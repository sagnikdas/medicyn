import 'package:drift/drift.dart';

import '../../core/ids.dart';
import '../../data/local/database.dart';
import '../../data/local/tables.dart';
import 'expected_doses.dart';

/// Records doses that were due and never answered.
///
/// Nothing has ever written [DoseAction.missed] — the value existed in the
/// enum and rendered in the history screen, but no code produced one. That
/// left a hole precisely where it hurts most: to someone reading a linked
/// person's feed, "ignored the alarm" and "not due yet" looked identical,
/// because both produced no row at all.
///
/// Runs on the device that owns the reminders, reusing its own idea of when
/// they were due. Detecting this server-side would mean a second
/// implementation of the recurrence rules, in another language, free to
/// drift out of agreement with the first about a medication schedule.
///
/// Only occurrences that were actually armed are judged — see [wasArmed]. A
/// reminder cannot be missed before it existed.
class MissedDoseDetector {
  const MissedDoseDetector();

  /// How long after a dose is due before it counts as missed. Long enough
  /// that a slow breakfast is not an incident; short enough that the answer
  /// still arrives while someone could act on it.
  static const grace = Duration(minutes: 30);

  /// How far back a single sweep will look. A phone left off over a weekend
  /// should come back and fill in what it missed, but there is no value in
  /// reconstructing last month — the reminders are gone and so is the
  /// chance to do anything about them.
  static const lookback = Duration(days: 3);

  /// Ceiling on one sweep, so a pathological schedule can't spend minutes
  /// writing rows on a foreground.
  static const _maxPerSweep = 200;

  /// Whether an occurrence at [due] was ever actually armed as an alarm, given
  /// a schedule last defined at [definedAt] ([Schedules.updatedAt]).
  ///
  /// This is the guard against inventing history. [expectedDoses] answers "when
  /// would this schedule have fired", with no idea when the schedule started
  /// existing — so without this, saving a reminder for 08:00 at nine in the
  /// morning immediately reports three days of 08:00 doses as skipped, for a
  /// reminder nobody had yet been asked to take. That is not a stale row in a
  /// list; since push landed it is a notification on a family member's phone
  /// telling them their mother stopped taking her medication.
  ///
  /// It bounds on `updatedAt` rather than `createdAt`, which is the stronger
  /// claim of the two. `createdAt` would fix the case above and still leave its
  /// twin: edit a reminder from 08:00 to 09:00 and the previous days get judged
  /// at 09:00, a time no alarm was ever set for. The alarms actually armed on
  /// the device always reflect the schedule's *current* definition — `reconcile`
  /// re-arms them from scratch on every foreground — so the last time that
  /// definition changed is the honest earliest point we can speak about.
  ///
  /// The cost is that an edit forfeits any not-yet-recorded backfill before it.
  /// That is a small and bounded loss: sweeps run on every foreground, so past
  /// occurrences have usually been judged already, and anything recorded stays
  /// recorded. It also sits the right way round with this file's rule that
  /// silence beats a false alarm.
  ///
  /// Strictly after, mirroring `_nextInstanceOfTime`'s own `isAfter(now)`: a
  /// dose due at the very instant a schedule was saved is not armed for today,
  /// it is armed for tomorrow.
  static bool wasArmed(DateTime due, {required DateTime definedAt}) =>
      due.isAfter(definedAt);

  /// Writes a missed log for every dose due in the lookback window that
  /// nothing answered. Returns how many were recorded.
  ///
  /// Idempotent: ids are derived from the schedule and the due time, so two
  /// sweeps — or two devices signed into the same account — converge on the
  /// same row rather than filling the feed with duplicates.
  Future<int> sweep(AppDatabase db, {DateTime? now, Duration? lookback}) async {
    final at = now ?? DateTime.now();
    final windowStart = at.subtract(lookback ?? MissedDoseDetector.lookback);
    // Nothing within the grace period is judged yet.
    final windowEnd = at.subtract(grace);
    if (!windowEnd.isAfter(windowStart)) return 0;

    final schedules = await db.activeSchedulesOnce();
    if (schedules.isEmpty) return 0;

    final logs = await db.doseLogsSince(windowStart);
    final byScheduleId = <String, List<DoseLog>>{};
    for (final log in logs) {
      byScheduleId.putIfAbsent(log.scheduleId, () => []).add(log);
    }

    final missed = <DoseLogsCompanion>[];
    for (final item in schedules) {
      final schedule = item.schedule;
      // Look a little past the cutoff so each occurrence knows when the next
      // one was, which is what bounds its answering window.
      final occurrences = expectedDoses(
        schedule,
        from: windowStart,
        to: at,
      );
      if (occurrences.isEmpty) continue;

      final scheduleLogs = byScheduleId[schedule.id] ?? const <DoseLog>[];
      for (var i = 0; i < occurrences.length; i++) {
        final due = occurrences[i];
        // Never happened as far as this device is concerned — the schedule did
        // not exist yet, or not in this shape. See [wasArmed].
        if (!wasArmed(due, definedAt: schedule.updatedAt)) continue;
        if (!due.isBefore(windowEnd)) continue; // still within grace
        // A response counts for this dose if it landed between this dose and
        // the next one. Matching on the log's own `scheduledAt` would be
        // more direct, but that value is reconstructed from a notification
        // payload and can carry the wrong date when someone answers late.
        final nextDue = i + 1 < occurrences.length ? occurrences[i + 1] : at;
        final answered = scheduleLogs.any(
          (log) => !log.loggedAt.isBefore(due) && log.loggedAt.isBefore(nextDue),
        );
        if (answered) continue;

        missed.add(DoseLogsCompanion.insert(
          id: missedDoseId(schedule.id, due),
          scheduleId: schedule.id,
          scheduledAt: due,
          action: DoseAction.missed.name,
          loggedAt: Value(due.add(grace)),
          source: const Value('auto'),
        ));
        if (missed.length >= _maxPerSweep) break;
      }
      if (missed.length >= _maxPerSweep) break;
    }

    if (missed.isEmpty) return 0;
    await db.recordMissedDoses(missed);
    return missed.length;
  }
}

/// A stable id for "this schedule's dose at this time", so the same missed
/// dose detected twice is the same row.
///
/// Keeps 24 hex digits of the schedule's own id and replaces the last 8 with
/// a hash of the due time: two schedules can't collide without sharing 96
/// bits of uuid, and two occurrences of one schedule can't without colliding
/// the hash of two different timestamps.
String missedDoseId(String scheduleId, DateTime scheduledAt) {
  final hex = scheduleId.replaceAll('-', '').toLowerCase();
  if (hex.length != 32 || !RegExp(r'^[0-9a-f]{32}$').hasMatch(hex)) {
    // Not a uuid we can build on. A random id still records the dose; it
    // just loses the de-duplication, which is better than losing the dose.
    return newUuid();
  }

  var hash = 0x811c9dc5; // FNV-1a, 32-bit
  for (final unit in scheduledAt.toUtc().toIso8601String().codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }

  final combined = hex.substring(0, 24) + hash.toRadixString(16).padLeft(8, '0');
  return '${combined.substring(0, 8)}-${combined.substring(8, 12)}-'
      '${combined.substring(12, 16)}-${combined.substring(16, 20)}-'
      '${combined.substring(20, 32)}';
}
