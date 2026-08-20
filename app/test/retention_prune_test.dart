import 'package:dosely/data/local/database.dart';
import 'package:dosely/data/local/tables.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  const scheduleId = '0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0';
  const medicineId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  final now = DateTime(2026, 8, 20, 12, 0);

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
      times: const ['09:00'],
    ));
  });

  tearDown(() async => db.close());

  test('drops dose logs older than 24 months and keeps recent ones', () async {
    await db.recordDoseAction(
      id: 'expired',
      scheduleId: scheduleId,
      scheduledAt: DateTime(2024, 7, 20, 12, 0),
      action: DoseAction.taken,
      loggedAt: DateTime(2024, 7, 20, 12, 0),
    );
    await db.recordDoseAction(
      id: 'recent',
      scheduleId: scheduleId,
      scheduledAt: DateTime(2026, 8, 13, 12, 0),
      action: DoseAction.taken,
      loggedAt: DateTime(2026, 8, 13, 12, 0),
    );

    final deleted = await db.pruneExpiredDoseLogs(now: now);

    expect(deleted, 1);
    final remaining = await db.doseLogsSince(DateTime(2020));
    expect(remaining, hasLength(1));
    expect(remaining.single.id, 'recent');
  });
}
