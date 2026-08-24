import 'package:dosely/data/local/database.dart';
import 'package:dosely/data/local/tables.dart';
import 'package:dosely/features/notification_engine/notification_actions.dart';
import 'package:dosely/features/reminders_home/refill.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers PR #68's third deferred finding: Taken used to decrement
/// `tabletsRemaining` in place, without bumping `updatedAt` (so the write
/// wouldn't itself win a version race). Whenever a pull then applied *any*
/// remote row for the same medicine — even one from a completely unrelated
/// edit — last-write-wins restored the old count and cleared the pending
/// sync flag, silently erasing the decrement.
///
/// The fix removes the in-place decrement entirely: `recordDoseTaken` only
/// ever writes a dose log, and the displayed count is derived from
/// `tabletsRemaining` (a baseline, changed only by an explicit save) minus
/// doses taken since that baseline was set. There is nothing left for a pull
/// to erase.
void main() {
  late AppDatabase db;

  const scheduleId = 'sched-1';
  const medicineId = 'med-1';
  final baseline = DateTime(2026, 8, 20, 9, 0);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.upsertMedicine(MedicinesCompanion.insert(
      id: medicineId,
      drugName: 'Metformin',
      tabletsRemaining: const Value(30),
      tabletsPerDose: const Value(1),
      updatedAt: Value(baseline),
      pendingSync: const Value(false),
    ));
    await db.upsertSchedule(SchedulesCompanion.insert(
      id: scheduleId,
      medicineId: medicineId,
      frequencyType: FrequencyType.daily.name,
      times: const ['09:00'],
    ));
  });

  tearDown(() async => db.close());

  /// Logs a Taken directly rather than through [recordDoseTaken], which
  /// stamps `loggedAt` from the wall clock — these tests need it fixed
  /// relative to [baseline] to stay deterministic regardless of when they
  /// actually run.
  Future<void> logTaken(String forSchedule, DateTime loggedAt) =>
      db.recordDoseAction(
        id: 'log-$forSchedule-$loggedAt',
        scheduleId: forSchedule,
        scheduledAt: baseline,
        action: DoseAction.taken,
        loggedAt: loggedAt,
      );

  test('a Taken dose is reflected in the derived count', () async {
    await logTaken(scheduleId, baseline.add(const Duration(minutes: 30)));
    final taken = await db.takenCountSince(scheduleId, baseline);
    final medicine = await db.medicineById(medicineId);
    expect(taken, 1);
    expect(derivedTabletsRemaining(medicine!, taken), 29);
  });

  test('recording Taken never touches the medicines row', () async {
    // This is the whole fix: nothing here can race a pull, because nothing
    // is written to `medicines` at all.
    await recordDoseTaken(
      db,
      scheduleId: scheduleId,
      scheduledAt: baseline,
      source: 'notification',
    );
    final medicine = await db.medicineById(medicineId);
    expect(medicine!.tabletsRemaining, 30, reason: 'baseline is untouched');
    expect(medicine.updatedAt, baseline, reason: 'not re-stamped');
    expect(medicine.pendingSync, isFalse, reason: 'not marked dirty');
  });

  test('a later edit re-baselines to the derived count, not the stale stored one', () async {
    // review_edit_screen's actual flow: load derives the live count, the
    // user edits something unrelated (say, the drug name), and save writes
    // that derived count back as the new baseline. Getting this wrong is
    // what would silently re-lose the dose taken below.
    await logTaken(scheduleId, baseline.add(const Duration(minutes: 30)));
    final taken = await db.takenCountSince(scheduleId, baseline);
    final loaded = await db.medicineById(medicineId);
    final derivedAtLoad = derivedTabletsRemaining(loaded!, taken);
    expect(derivedAtLoad, 29);

    final savedAt = baseline.add(const Duration(hours: 1));
    await db.upsertMedicine(MedicinesCompanion(
      id: const Value(medicineId),
      drugName: const Value('Metformin XR'),
      tabletsRemaining: Value(derivedAtLoad),
      tabletsPerDose: const Value(1),
      updatedAt: Value(savedAt),
      pendingSync: const Value(true),
    ));

    final resaved = await db.medicineById(medicineId);
    final takenSinceResave = await db.takenCountSince(scheduleId, savedAt);
    expect(takenSinceResave, 0, reason: 'the dose is already folded into the new baseline');
    expect(derivedTabletsRemaining(resaved!, takenSinceResave), 29);
  });

  test('takenCountsSinceBaseline sums every schedule against one medicine', () async {
    const secondScheduleId = 'sched-2';
    await db.upsertSchedule(SchedulesCompanion.insert(
      id: secondScheduleId,
      medicineId: medicineId,
      frequencyType: FrequencyType.daily.name,
      times: const ['21:00'],
    ));
    await logTaken(scheduleId, baseline.add(const Duration(minutes: 30)));
    await logTaken(secondScheduleId, baseline.add(const Duration(minutes: 45)));

    final items = await db.schedulesWithMedicinesOnce();
    final counts = await db.takenCountsSinceBaseline(items);

    expect(counts[medicineId], 2);
  });
}
