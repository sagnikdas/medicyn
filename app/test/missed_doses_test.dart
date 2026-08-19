import 'package:dosely/data/local/database.dart';
import 'package:dosely/data/local/tables.dart';
import 'package:dosely/features/notification_engine/missed_doses.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The sweep decides whether a dose is reported to a family member as
/// skipped. Both directions of error are bad and they are bad differently: a
/// false positive tells someone their parent missed medication when they did
/// not, and a false negative is the silence this feature exists to remove.
void main() {
  late AppDatabase db;

  // A Wednesday, with reminders at 08:00 and 20:00.
  final now = DateTime(2026, 8, 19, 12, 0);
  const scheduleId = '0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0';
  const medicineId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.upsertMedicine(MedicinesCompanion.insert(
      id: medicineId,
      drugName: 'Metformin',
    ));
  });

  tearDown(() async => db.close());

  // Well before any window these tests use, so the schedule counts as having
  // existed all along. It has to be stated rather than defaulted: the column
  // defaults to the real wall clock, which for a sweep at a *simulated* `now`
  // would put every occurrence before the schedule existed — and correctly
  // produce nothing. See [MissedDoseDetector.wasArmed].
  final longEstablished = DateTime(2026, 8, 1);

  Future<void> givenSchedule({
    List<String> times = const ['08:00', '20:00'],
    FrequencyType frequency = FrequencyType.daily,
    DateTime? definedAt,
  }) async {
    await db.upsertSchedule(SchedulesCompanion.insert(
      id: scheduleId,
      medicineId: medicineId,
      frequencyType: frequency.name,
      times: times,
      updatedAt: Value(definedAt ?? longEstablished),
    ));
  }

  Future<void> givenLog({
    required DateTime loggedAt,
    DoseAction action = DoseAction.taken,
  }) async {
    await db.recordDoseAction(
      id: 'log-${loggedAt.millisecondsSinceEpoch}',
      scheduleId: scheduleId,
      scheduledAt: loggedAt,
      action: action,
      loggedAt: loggedAt,
    );
  }

  Future<int> sweep({Duration? lookback}) =>
      const MissedDoseDetector().sweep(db, now: now, lookback: lookback);

  Future<List<DoseLog>> missedLogs() async {
    final logs = await db.doseLogsSince(DateTime(2026, 8, 1));
    return logs.where((l) => l.action == DoseAction.missed.name).toList();
  }

  test('records a dose nobody answered', () async {
    await givenSchedule(times: ['08:00']);

    final count = await sweep(lookback: const Duration(hours: 6));

    expect(count, 1);
    final missed = await missedLogs();
    expect(missed.single.scheduledAt, DateTime(2026, 8, 19, 8, 0));
    expect(missed.single.source, 'auto');
  });

  test('reaches back over every day in its window', () async {
    // The real three-day lookback, so a phone left off over a weekend comes
    // back and fills in what it could not see at the time.
    await givenSchedule(times: ['08:00']);

    final count = await sweep();

    // 16 Aug 08:00 falls before the window opens at 16 Aug 12:00.
    expect(count, 3);
    final missed = await missedLogs();
    expect(
      missed.map((l) => l.scheduledAt).toSet(),
      {
        DateTime(2026, 8, 17, 8, 0),
        DateTime(2026, 8, 18, 8, 0),
        DateTime(2026, 8, 19, 8, 0),
      },
    );
  });

  test('leaves an answered dose alone', () async {
    await givenSchedule(times: ['08:00']);
    await givenLog(loggedAt: DateTime(2026, 8, 19, 8, 4));

    final count = await sweep(lookback: const Duration(hours: 6));

    expect(count, 0);
    expect(await missedLogs(), isEmpty);
  });

  test('counts a late answer for the dose it belongs to, not the next one', () async {
    // Answered at 09:30 — well after 08:00, but long before 20:00. This is
    // why the rule is "answered before the next dose" rather than a fixed
    // window: someone who takes a tablet an hour late has not missed it.
    await givenSchedule();
    await givenLog(loggedAt: DateTime(2026, 8, 19, 9, 30));

    await sweep(lookback: const Duration(hours: 6));

    expect(await missedLogs(), isEmpty);
  });

  test('does not judge a dose still inside its grace period', () async {
    // Due 11:45, swept at 12:00, grace is 30 minutes.
    await givenSchedule(times: ['11:45']);

    final count = await sweep(lookback: const Duration(hours: 6));

    expect(count, 0);
  });

  test('does judge a dose once the grace period has passed', () async {
    // Due 11:00, swept at 12:00.
    await givenSchedule(times: ['11:00']);

    final count = await sweep(lookback: const Duration(hours: 6));

    expect(count, 1);
  });

  test('sweeping twice does not duplicate a missed dose', () async {
    await givenSchedule(times: ['08:00']);

    final first = await sweep(lookback: const Duration(hours: 6));
    final second = await sweep(lookback: const Duration(hours: 6));

    expect(first, 1);
    // Nothing new the second time: the missed row written by the first sweep
    // is itself an entry against that dose, so the dose is no longer
    // unanswered. The deterministic id is the belt to that braces — even a
    // sweep from a second device lands on the same row.
    expect(second, 0);
    expect(await missedLogs(), hasLength(1));
  });

  test('ignores an inactive schedule', () async {
    await givenSchedule(times: ['08:00']);
    await db.deactivateSchedule(scheduleId);

    final count = await sweep(lookback: const Duration(hours: 6));

    expect(count, 0);
  });

  test('ignores an as-needed schedule, which has no due time to miss', () async {
    await givenSchedule(times: ['08:00'], frequency: FrequencyType.asNeeded);

    final count = await sweep(lookback: const Duration(hours: 6));

    expect(count, 0);
  });

  test('marks the missed rows for sync so the other side sees them', () async {
    await givenSchedule(times: ['08:00']);

    await sweep(lookback: const Duration(hours: 6));

    final unsynced = await db.unsyncedDoseLogs();
    expect(unsynced.where((l) => l.action == DoseAction.missed.name), isNotEmpty);
  });

  /// A reminder cannot be missed before it existed.
  ///
  /// [expectedDoses] answers "when would this schedule have fired", knowing
  /// nothing about when the schedule came into being — so an unbounded sweep
  /// invents history. It is the sharpest false positive the whole feature can
  /// produce: adding a medicine at nine in the morning would announce three
  /// days of eight o'clock doses as skipped, doses nobody was ever asked to
  /// take. Since push landed that is not a stale row in a list, it is a
  /// notification on a family member's phone.
  group('a dose before the schedule was defined', () {
    test('is not reported for a reminder saved after it was due', () async {
      // Saved at 10:00; the 08:00 alarm that morning was never armed.
      await givenSchedule(
        times: ['08:00'],
        definedAt: DateTime(2026, 8, 19, 10, 0),
      );

      final count = await sweep(lookback: const Duration(hours: 6));

      expect(count, 0);
      expect(await missedLogs(), isEmpty);
    });

    test('is reported for a reminder saved before it was due', () async {
      // Saved at 07:00, so the 08:00 alarm really was armed and really was
      // ignored. The bound must not cost the true positives.
      await givenSchedule(
        times: ['08:00'],
        definedAt: DateTime(2026, 8, 19, 7, 0),
      );

      final count = await sweep(lookback: const Duration(hours: 6));

      expect(count, 1);
      expect((await missedLogs()).single.scheduledAt, DateTime(2026, 8, 19, 8, 0));
    });

    test('does not backfill the days before a reminder was added', () async {
      // The bug as it actually appeared in production data: a schedule added
      // this morning carrying missed doses dated three days earlier.
      await givenSchedule(
        times: ['08:00'],
        definedAt: DateTime(2026, 8, 19, 7, 0),
      );

      final count = await sweep(lookback: const Duration(days: 3));

      expect(count, 1, reason: 'only today, not the three days before it existed');
      final missed = await missedLogs();
      expect(missed.map((l) => l.scheduledAt), [DateTime(2026, 8, 19, 8, 0)]);
    });

    test('does not judge earlier days at a time that was only just set', () async {
      // The twin case, and why the bound is `updatedAt` and not `createdAt`:
      // this schedule may have existed for weeks, but its 08:00 was set an
      // hour ago. Yesterday's alarm rang at some other time, or not at all —
      // either way, 08:00 yesterday is a time no alarm was ever set for.
      await givenSchedule(
        times: ['08:00'],
        definedAt: DateTime(2026, 8, 19, 7, 0),
      );

      await sweep(lookback: const Duration(days: 3));

      final missed = await missedLogs();
      expect(
        missed.every((l) => l.scheduledAt.isAfter(DateTime(2026, 8, 19, 7, 0))),
        isTrue,
      );
    });

    test('a dose due at the very instant of the save is armed for tomorrow', () async {
      // Mirrors _nextInstanceOfTime's own `isAfter(now)`: save at exactly
      // 08:00 and today's 08:00 has already gone, so the alarm is set for
      // tomorrow and today's occurrence was never armed.
      await givenSchedule(
        times: ['08:00'],
        definedAt: DateTime(2026, 8, 19, 8, 0),
      );

      expect(await sweep(lookback: const Duration(hours: 6)), 0);
    });

    test('an established reminder is unaffected', () async {
      // The guard must be invisible to the ordinary case, which is every
      // reminder that has been sitting there since before the window.
      await givenSchedule(times: ['08:00'], definedAt: longEstablished);

      expect(await sweep(lookback: const Duration(days: 3)), 3);
    });
  });

  group('wasArmed', () {
    final definedAt = DateTime(2026, 8, 19, 8, 0);

    test('a dose after the definition was armed', () {
      expect(
        MissedDoseDetector.wasArmed(DateTime(2026, 8, 19, 8, 1), definedAt: definedAt),
        isTrue,
      );
    });

    test('a dose before the definition was not', () {
      expect(
        MissedDoseDetector.wasArmed(DateTime(2026, 8, 19, 7, 59), definedAt: definedAt),
        isFalse,
      );
    });

    test('a dose exactly at the definition was not', () {
      expect(MissedDoseDetector.wasArmed(definedAt, definedAt: definedAt), isFalse);
    });
  });
}
