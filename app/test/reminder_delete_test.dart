import 'package:medicyn/data/local/database.dart';
import 'package:medicyn/data/local/tables.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// "Remove this reminder" used to only set `active = false`. The medicine
/// row and its dose logs stayed, so a linked family member kept seeing the
/// history. These two actions have to do what they say.
void main() {
  late AppDatabase db;

  const medicineId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  const scheduleId = '0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0';
  const logId = '11111111-2222-3333-4444-555555555555';
  final due = DateTime(2026, 8, 19, 8, 0);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.upsertMedicine(MedicinesCompanion.insert(
      id: medicineId,
      drugName: 'Metformin',
    ));
    await db.upsertSchedule(SchedulesCompanion.insert(
      id: scheduleId,
      medicineId: medicineId,
      frequencyType: FrequencyType.daily.name,
      times: const ['08:00'],
    ));
    await db.recordDoseAction(
      id: logId,
      scheduleId: scheduleId,
      scheduledAt: due,
      action: DoseAction.taken,
      loggedAt: due,
    );
  });

  tearDown(() async => db.close());

  test('stop reminding leaves the medicine and its dose history', () async {
    await db.deactivateSchedule(scheduleId, by: 'user-1');

    final medicine = await db.medicineById(medicineId);
    expect(medicine, isNotNull);
    expect(medicine!.deleted, isFalse);

    final schedule = await db.scheduleById(scheduleId);
    expect(schedule, isNotNull);
    expect(schedule!.active, isFalse);
    expect(schedule.deleted, isFalse);
    expect(schedule.pendingSync, isTrue);
    expect(schedule.updatedBy, 'user-1');

    final logs = await db.watchDoseLogsForSchedule(scheduleId).first;
    expect(logs, hasLength(1));
    expect(logs.single.id, logId);

    final active = await db.watchActiveSchedules().first;
    expect(active, isEmpty);
  });

  test('delete medicine and history tombstones rows and drops dose logs', () async {
    await db.deleteMedicineAndHistory(medicineId, by: 'user-1');

    final medicine = await db.medicineById(medicineId);
    expect(medicine, isNotNull);
    expect(medicine!.deleted, isTrue);
    expect(medicine.pendingSync, isTrue);
    expect(medicine.updatedBy, 'user-1');

    final schedule = await db.scheduleById(scheduleId);
    expect(schedule, isNotNull);
    expect(schedule!.deleted, isTrue);
    expect(schedule.active, isFalse);
    expect(schedule.pendingSync, isTrue);
    expect(schedule.updatedBy, 'user-1');

    expect(await db.watchDoseLogsForSchedule(scheduleId).first, isEmpty);
    expect(await db.watchActiveSchedules().first, isEmpty);
  });

  test('a deleted local medicine is not resurrected by a stale remote copy', () async {
    await db.deleteMedicineAndHistory(medicineId, by: 'user-1');

    await db.applyRemoteMedicines([
      MedicinesCompanion.insert(
        id: medicineId,
        drugName: 'Metformin',
        pendingSync: const Value(false),
      ),
    ]);
    await db.applyRemoteSchedules([
      SchedulesCompanion.insert(
        id: scheduleId,
        medicineId: medicineId,
        frequencyType: FrequencyType.daily.name,
        times: const ['08:00'],
        active: const Value(true),
        pendingSync: const Value(false),
      ),
    ]);
    await db.applyRemoteDoseLogs([
      DoseLogsCompanion.insert(
        id: logId,
        scheduleId: scheduleId,
        scheduledAt: due,
        action: DoseAction.taken.name,
        pendingSync: const Value(false),
      ),
    ]);

    final medicine = await db.medicineById(medicineId);
    expect(medicine!.deleted, isTrue);
    expect(medicine.pendingSync, isTrue);

    final schedule = await db.scheduleById(scheduleId);
    expect(schedule!.deleted, isTrue);
    expect(schedule.active, isFalse);
    expect(schedule.pendingSync, isTrue);

    expect(await db.watchDoseLogsForSchedule(scheduleId).first, isEmpty);
    expect(await db.watchActiveSchedules().first, isEmpty);
  });
}
