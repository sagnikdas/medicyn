import 'package:dosely/data/local/database.dart';
import 'package:dosely/data/local/tables.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The local database is the source of truth for what actually happened.
/// These cover the writes whose side effects reach other people: the pill
/// count a refill warning is drawn from, and the set of missed doses the
/// server is asked to announce to a caregiver.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> seed({
    int? remaining,
    int? perDose,
    DateTime? medicineUpdatedAt,
  }) async {
    await db.upsertMedicine(MedicinesCompanion.insert(
      id: 'med-1',
      drugName: 'Metformin',
      tabletsRemaining: Value(remaining),
      tabletsPerDose: Value(perDose),
      updatedAt: Value(medicineUpdatedAt ?? DateTime(2026, 8, 1)),
      pendingSync: const Value(false),
    ));
    await db.upsertSchedule(SchedulesCompanion.insert(
      id: 'sched-1',
      medicineId: 'med-1',
      frequencyType: 'daily',
      times: const <String>['08:00'],
      daysOfWeek: const Value(<int>[]),
      pendingSync: const Value(false),
    ));
  }

  group('syncedMissedDoseIdsSince', () {
    Future<void> log(
      String id, {
      required DoseAction action,
      required DateTime loggedAt,
      bool pendingSync = false,
    }) async {
      await db.into(db.doseLogs).insert(DoseLogsCompanion.insert(
            id: id,
            scheduleId: 'sched-1',
            scheduledAt: loggedAt,
            action: action.name,
            loggedAt: Value(loggedAt),
            pendingSync: Value(pendingSync),
          ));
    }

    final now = DateTime(2026, 8, 21, 12);

    setUp(() => seed(remaining: 30));

    test('names a missed dose the server already has', () async {
      await log('a', action: DoseAction.missed, loggedAt: now);
      expect(
        await db.syncedMissedDoseIdsSince(now.subtract(const Duration(hours: 6))),
        ['a'],
      );
    });

    test('never names one still only on this phone', () async {
      // The server composes the alert text from the row; naming a row it
      // cannot read means a caregiver is told nothing at all.
      await log('a', action: DoseAction.missed, loggedAt: now, pendingSync: true);
      expect(
        await db.syncedMissedDoseIdsSince(now.subtract(const Duration(hours: 6))),
        isEmpty,
      );
    });

    test('ignores taken and snoozed', () async {
      await log('t', action: DoseAction.taken, loggedAt: now);
      await log('s', action: DoseAction.snoozed, loggedAt: now);
      expect(
        await db.syncedMissedDoseIdsSince(now.subtract(const Duration(hours: 6))),
        isEmpty,
      );
    });

    test('ignores anything older than the window', () async {
      await log('old', action: DoseAction.missed, loggedAt: now.subtract(const Duration(days: 2)));
      await log('new', action: DoseAction.missed, loggedAt: now);
      expect(
        await db.syncedMissedDoseIdsSince(now.subtract(const Duration(hours: 6))),
        ['new'],
      );
    });

    test('a phone back from a long absence sends a bounded list, newest first',
        () async {
      for (var i = 0; i < 10; i++) {
        await log('m$i',
            action: DoseAction.missed,
            loggedAt: now.subtract(Duration(minutes: i)));
      }
      final ids = await db.syncedMissedDoseIdsSince(
        now.subtract(const Duration(days: 30)),
        limit: 3,
      );
      expect(ids, ['m0', 'm1', 'm2']);
    });
  });

  group('deleteMedicineAndHistory', () {
    test('drops the history but keeps tombstones a pull can see', () async {
      await seed(remaining: 30);
      await db.recordDoseAction(
        id: 'log-1',
        scheduleId: 'sched-1',
        scheduledAt: DateTime(2026, 8, 20, 8),
        action: DoseAction.taken,
      );
      await db.upsertDoseLogContest(doseLogId: 'log-1', note: 'I did take it');

      await db.deleteMedicineAndHistory('med-1', by: 'me');

      expect(await db.doseLogById('log-1'), isNull);
      expect(await db.contestForDoseLog('log-1'), isNull);
      final med = (await db.medicineById('med-1'))!;
      expect(med.deleted, isTrue);
      expect(med.pendingSync, isTrue);
      final sched = (await db.scheduleById('sched-1'))!;
      expect(sched.deleted, isTrue);
      expect(sched.active, isFalse,
          reason: 'a deleted medicine must not keep arming alarms');
      expect(sched.updatedBy, 'me');
    });
  });
}
