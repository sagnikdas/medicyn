import 'package:medicyn/data/local/database.dart';
import 'package:medicyn/data/local/tables.dart';
import 'package:drift/drift.dart' show Value;
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

  test('a pruned log takes its contest note with it', () async {
    // DoseLogContests declares onDelete: cascade, but nothing enables
    // PRAGMA foreign_keys for this database, so SQLite never fires it. The
    // note is free-text health data; outliving its log means it is kept
    // past the retention period the privacy policy states, and orphaned
    // from the dose it was written about.
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.upsertMedicine(
        MedicinesCompanion.insert(id: 'med-1', drugName: 'Metformin'));
    await db.upsertSchedule(SchedulesCompanion.insert(
      id: 'sched-1',
      medicineId: 'med-1',
      frequencyType: 'daily',
      times: const <String>['08:00'],
      daysOfWeek: const Value(<int>[]),
    ));

    final now = DateTime(2026, 8, 21, 12);
    final expired = DateTime(2024, 1, 1);
    final recent = DateTime(2026, 8, 20);
    for (final (id, at) in [('old', expired), ('new', recent)]) {
      await db.recordDoseAction(
        id: id,
        scheduleId: 'sched-1',
        scheduledAt: at,
        action: DoseAction.taken,
        loggedAt: at,
      );
      await db.upsertDoseLogContest(doseLogId: id, note: 'note on $id');
    }

    expect(await db.pruneExpiredDoseLogs(now: now), 1);

    expect(await db.contestForDoseLog('old'), isNull,
        reason: 'the note must go with the log it annotates');
    expect((await db.contestForDoseLog('new'))!.note, 'note on new',
        reason: 'a note inside the retention window is untouched');
  });
}
