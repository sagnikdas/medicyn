import 'package:dosely/data/local/database.dart';
import 'package:dosely/data/local/tables.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  const medicineId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  const scheduleId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  const logId = 'cccccccc-cccc-cccc-cccc-cccccccccccc';

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
    await db.recordDoseAction(
      id: logId,
      scheduleId: scheduleId,
      scheduledAt: DateTime.utc(2026, 8, 20, 9),
      action: DoseAction.missed,
      loggedAt: DateTime.utc(2026, 8, 20, 10),
    );
  });

  tearDown(() async => db.close());

  test('saving a note does not change dose_logs.action and is readable back', () async {
    final before = await db.doseLogById(logId);
    expect(before!.action, DoseAction.missed.name);

    await db.upsertDoseLogContest(
      doseLogId: logId,
      note: 'I did take this; the reminder never showed.',
    );

    final after = await db.doseLogById(logId);
    expect(after!.action, DoseAction.missed.name);
    expect(after.scheduledAt, before.scheduledAt);
    expect(after.loggedAt, before.loggedAt);

    final contest = await db.contestForDoseLog(logId);
    expect(contest, isNotNull);
    expect(contest!.note, 'I did take this; the reminder never showed.');
  });

  test('editing a note still leaves the log action alone', () async {
    await db.upsertDoseLogContest(doseLogId: logId, note: 'first');
    await db.upsertDoseLogContest(doseLogId: logId, note: 'second look');

    final log = await db.doseLogById(logId);
    expect(log!.action, DoseAction.missed.name);
    final contest = await db.contestForDoseLog(logId);
    expect(contest!.note, 'second look');
  });
}
