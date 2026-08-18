import 'package:dosely/data/local/database.dart';
import 'package:dosely/data/local/tables.dart';
import 'package:dosely/features/notification_engine/missed_doses.dart';
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

  Future<void> givenSchedule({
    List<String> times = const ['08:00', '20:00'],
    FrequencyType frequency = FrequencyType.daily,
  }) async {
    await db.upsertSchedule(SchedulesCompanion.insert(
      id: scheduleId,
      medicineId: medicineId,
      frequencyType: frequency.name,
      times: times,
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
}
