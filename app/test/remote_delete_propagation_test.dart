import 'package:medicyn/data/local/database.dart';
import 'package:medicyn/data/local/tables.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers PR #68's finding that a delete never propagated on pull: deletes
/// are hard DELETEs server-side with no tombstone column, so pull only ever
/// added/updated rows and never noticed one was gone. A second device kept
/// ringing forever for a medicine stopped elsewhere.
///
/// The fix has SyncService compare what a pull actually got back against
/// what this device already believes is synced, and tombstone anything
/// missing. These tests cover the database-layer query and write that
/// decision is built on; the network call itself isn't covered here (no
/// fake Supabase transport lives on this branch yet).
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  group('medicineIdsMissingRemotely', () {
    test('a synced medicine absent from the remote set is missing', () async {
      await db.upsertMedicine(MedicinesCompanion.insert(
        id: 'm1',
        drugName: 'Metformin',
        pendingSync: const Value(false),
      ));
      final missing = await db.medicineIdsMissingRemotely(const {});
      expect(missing, ['m1']);
    });

    test('a medicine present in the remote set is not missing', () async {
      await db.upsertMedicine(MedicinesCompanion.insert(
        id: 'm1',
        drugName: 'Metformin',
        pendingSync: const Value(false),
      ));
      expect(await db.medicineIdsMissingRemotely({'m1'}), isEmpty);
    });

    test('a pending local edit is never treated as missing', () async {
      // Not yet pushed — its absence from a remote SELECT means nothing.
      await db.upsertMedicine(MedicinesCompanion.insert(
        id: 'm1',
        drugName: 'Metformin',
        pendingSync: const Value(true),
      ));
      expect(await db.medicineIdsMissingRemotely(const {}), isEmpty);
    });

    test('an already-tombstoned medicine is not reported again', () async {
      await db.upsertMedicine(MedicinesCompanion.insert(
        id: 'm1',
        drugName: 'Metformin',
        pendingSync: const Value(false),
        deleted: const Value(true),
      ));
      expect(await db.medicineIdsMissingRemotely(const {}), isEmpty);
    });
  });

  group('tombstoneMedicinesMissingRemotely', () {
    test('marks the row deleted without leaving anything to push', () async {
      await db.upsertMedicine(MedicinesCompanion.insert(
        id: 'm1',
        drugName: 'Metformin',
        pendingSync: const Value(false),
      ));
      await db.tombstoneMedicinesMissingRemotely(['m1']);
      final medicine = await db.medicineById('m1');
      expect(medicine!.deleted, isTrue);
      expect(medicine.pendingSync, isFalse);
    });
  });

  group('scheduleIdsMissingRemotely / tombstoneSchedulesMissingRemotely', () {
    test('a schedule whose medicine was deleted elsewhere stops arming', () async {
      await db.upsertMedicine(MedicinesCompanion.insert(
        id: 'm1',
        drugName: 'Metformin',
        pendingSync: const Value(false),
      ));
      await db.upsertSchedule(SchedulesCompanion.insert(
        id: 's1',
        medicineId: 'm1',
        frequencyType: FrequencyType.daily.name,
        times: const ['09:00'],
        active: const Value(true),
        pendingSync: const Value(false),
      ));
      final missing = await db.scheduleIdsMissingRemotely(const {});
      expect(missing, ['s1']);

      await db.tombstoneSchedulesMissingRemotely(missing);
      final schedule = await db.scheduleById('s1');
      expect(schedule!.deleted, isTrue);
      expect(schedule.active, isFalse);
      expect(schedule.pendingSync, isFalse);
    });
  });
}
