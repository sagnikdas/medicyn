import 'package:medicyn/data/local/database.dart';
import 'package:medicyn/data/local/tables.dart';
import 'package:medicyn/features/notification_engine/notification_actions.dart';
import 'package:medicyn/features/reminders_home/refill.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// An as-needed (PRN) medicine has no schedule to generate occurrences from
/// — `expectedDoses` returns `[]` for it on purpose — so "Log now" is the
/// only way one of these ever reaches `dose_logs`. These tests exercise
/// [recordAsNeededDoseTaken] the same way `snooze_and_alarm_test.dart`
/// exercises [recordDoseTaken] for scheduled reminders: it should be the
/// same underlying write, just keyed to "now" instead of a due time.
void main() {
  const scheduleId = '1a2b3c4d-5e6f-7890-abcd-ef0123456789';
  const medicineId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.upsertMedicine(
      MedicinesCompanion.insert(
        id: medicineId,
        drugName: 'Ibuprofen',
        tabletsRemaining: const Value(20),
        tabletsPerDose: const Value(1),
        updatedAt: Value(DateTime(2020, 1, 1)),
      ),
    );
    await db.upsertSchedule(
      SchedulesCompanion.insert(
        id: scheduleId,
        medicineId: medicineId,
        frequencyType: FrequencyType.asNeeded.name,
        times: const <String>[],
        daysOfWeek: const Value(<int>[]),
      ),
    );
  });
  tearDown(() => db.close());

  Future<List<DoseLog>> logs() =>
      db.watchDoseLogsForSchedule(scheduleId).first;

  Future<int?> remaining() async {
    final medicine = (await db.medicineById(medicineId))!;
    final taken = await db.takenCountSince(scheduleId, medicine.updatedAt);
    return derivedTabletsRemaining(medicine, taken);
  }

  test('logs Taken at the given time', () async {
    final at = DateTime(2026, 8, 26, 14, 30);
    await recordAsNeededDoseTaken(db, scheduleId: scheduleId, at: at);

    final all = await logs();
    expect(all, hasLength(1));
    expect(all.single.action, DoseAction.taken.name);
    expect(all.single.scheduledAt, at);
  });

  test('defaults to right now when no time is given', () async {
    final before = DateTime.now();
    await recordAsNeededDoseTaken(db, scheduleId: scheduleId);
    final after = DateTime.now();

    final logged = (await logs()).single.scheduledAt;
    expect(
      !logged.isBefore(before) && !logged.isAfter(after),
      isTrue,
      reason: 'expected $logged to fall between $before and $after',
    );
  });

  test('records with a manual source, distinct from a notification tap', () async {
    await recordAsNeededDoseTaken(db, scheduleId: scheduleId);
    expect((await logs()).single.source, 'manual');
  });

  test('two presses on two different days are two separate doses', () async {
    final morning = DateTime(2026, 8, 26, 9);
    final evening = DateTime(2026, 8, 26, 21);
    await recordAsNeededDoseTaken(db, scheduleId: scheduleId, at: morning);
    await recordAsNeededDoseTaken(db, scheduleId: scheduleId, at: evening);

    expect(await logs(), hasLength(2));
    expect(await remaining(), 18, reason: 'each press takes its own tablet');
  });

  test(
    'reuses the same dose-log plumbing a scheduled Taken uses, so stock '
    'still derives correctly',
    () async {
      await recordAsNeededDoseTaken(
        db,
        scheduleId: scheduleId,
        at: DateTime(2026, 8, 26, 9),
      );
      expect(await remaining(), 19);
    },
  );
}
