import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';

import 'converters.dart';
import 'tables.dart';

part 'database.g.dart';

/// A row combining a schedule with its parent medicine — the shape most
/// screens (home list, notification engine) actually want.
class ScheduleWithMedicine {
  final Schedule schedule;
  final Medicine medicine;
  ScheduleWithMedicine(this.schedule, this.medicine);
}

@DriftDatabase(tables: [Medicines, Schedules, DoseLogs])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'dosely'));

  /// For tests: an isolated database with no file behind it, so logic that
  /// spans several tables can be exercised without a device.
  @visibleForTesting
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // Row versioning, so a pull can overwrite an older local copy
            // instead of only inserting rows it has never seen.
            await m.addColumn(medicines, medicines.updatedAt);
            await m.addColumn(medicines, medicines.updatedBy);
            await m.addColumn(schedules, schedules.updatedAt);
            await m.addColumn(schedules, schedules.updatedBy);
            // Existing rows have never been edited, so their last change was
            // their creation. The column default would otherwise stamp them
            // all with the moment of upgrade, letting them beat genuinely
            // newer edits waiting on the server.
            await customStatement('UPDATE medicines SET updated_at = created_at');
            await customStatement('UPDATE schedules SET updated_at = created_at');
          }
        },
      );

  // --- Medicines ---------------------------------------------------------

  Future<void> upsertMedicine(MedicinesCompanion row) =>
      into(medicines).insertOnConflictUpdate(row);

  Future<Medicine?> medicineById(String id) =>
      (select(medicines)..where((t) => t.id.equals(id))).getSingleOrNull();

  // --- Schedules -----------------------------------------------------------

  Future<void> upsertSchedule(SchedulesCompanion row) =>
      into(schedules).insertOnConflictUpdate(row);

  Future<Schedule?> scheduleById(String id) =>
      (select(schedules)..where((t) => t.id.equals(id))).getSingleOrNull();

  Stream<List<ScheduleWithMedicine>> watchActiveSchedules() {
    final query = select(schedules).join([
      innerJoin(medicines, medicines.id.equalsExp(schedules.medicineId)),
    ])
      ..where(schedules.active.equals(true) & schedules.deleted.equals(false));
    return query.watch().map(
          (rows) => rows
              .map((r) => ScheduleWithMedicine(
                    r.readTable(schedules),
                    r.readTable(medicines),
                  ))
              .toList(),
        );
  }

  Future<List<ScheduleWithMedicine>> activeSchedulesOnce() async {
    final query = select(schedules).join([
      innerJoin(medicines, medicines.id.equalsExp(schedules.medicineId)),
    ])
      ..where(schedules.active.equals(true) & schedules.deleted.equals(false));
    final rows = await query.get();
    return rows
        .map((r) => ScheduleWithMedicine(
              r.readTable(schedules),
              r.readTable(medicines),
            ))
        .toList();
  }

  /// Turning a reminder off is an edit like any other, so it has to carry a
  /// fresh [Schedules.updatedAt]. Without one it loses every version
  /// comparison against the server's still-active copy, and the reminder
  /// reappears on the next pull.
  Future<void> deactivateSchedule(String id, {String? by}) =>
      (update(schedules)..where((t) => t.id.equals(id))).write(
        SchedulesCompanion(
          active: const Value(false),
          pendingSync: const Value(true),
          updatedAt: Value(DateTime.now()),
          updatedBy: Value(by),
        ),
      );

  // --- Dose logs -----------------------------------------------------------

  /// [loggedAt] defaults to now, which is right for a live response. It is
  /// accepted so a caller that already knows when the action happened — a
  /// backfill, or a test simulating a particular day — can say so instead of
  /// having the column's default overwrite it.
  Future<void> recordDoseAction({
    required String id,
    required String scheduleId,
    required DateTime scheduledAt,
    required DoseAction action,
    String source = 'notification',
    DateTime? loggedAt,
  }) {
    return into(doseLogs).insertOnConflictUpdate(
      DoseLogsCompanion.insert(
        id: id,
        scheduleId: scheduleId,
        scheduledAt: scheduledAt,
        action: action.name,
        source: Value(source),
        loggedAt: loggedAt == null ? const Value.absent() : Value(loggedAt),
      ),
    );
  }

  Stream<List<DoseLog>> watchDoseLogsForSchedule(String scheduleId) =>
      (select(doseLogs)..where((t) => t.scheduleId.equals(scheduleId))).watch();

  /// Most recent dose log for a schedule, if any. One-shot rather than
  /// reactive: the notification engine records Taken/Snooze from its own
  /// `AppDatabase` instance (often a different isolate entirely), and those
  /// writes don't push to a `.watch()` stream opened on this one — so
  /// callers that need this fresh must re-poll.
  Future<DoseLog?> latestDoseLogOnce(String scheduleId) => (select(doseLogs)
        ..where((t) => t.scheduleId.equals(scheduleId))
        ..orderBy([(t) => OrderingTerm.desc(t.loggedAt)])
        ..limit(1))
      .getSingleOrNull();

  /// Every dose log written since [since], across all schedules — one query
  /// for a missed-dose sweep rather than one per reminder.
  Future<List<DoseLog>> doseLogsSince(DateTime since) =>
      (select(doseLogs)..where((t) => t.loggedAt.isBiggerOrEqualValue(since))).get();

  /// Insert-or-ignore, because missed doses carry deterministic ids: a sweep
  /// that runs twice, or on a second device, must converge on the same row
  /// rather than filling the feed with duplicates of the same skipped dose.
  Future<void> recordMissedDoses(List<DoseLogsCompanion> rows) async {
    if (rows.isEmpty) return;
    await batch((b) => b.insertAll(doseLogs, rows, mode: InsertMode.insertOrIgnore));
  }

  // --- Sync helpers ----------------------------------------------------

  Future<List<Medicine>> unsyncedMedicines() =>
      (select(medicines)..where((t) => t.pendingSync.equals(true))).get();

  Future<List<Schedule>> unsyncedSchedules() =>
      (select(schedules)..where((t) => t.pendingSync.equals(true))).get();

  Future<List<DoseLog>> unsyncedDoseLogs() =>
      (select(doseLogs)..where((t) => t.pendingSync.equals(true))).get();

  Future<void> markMedicineSynced(String id) =>
      (update(medicines)..where((t) => t.id.equals(id)))
          .write(const MedicinesCompanion(pendingSync: Value(false)));

  Future<void> markScheduleSynced(String id) =>
      (update(schedules)..where((t) => t.id.equals(id)))
          .write(const SchedulesCompanion(pendingSync: Value(false)));

  Future<void> markDoseLogSynced(String id) =>
      (update(doseLogs)..where((t) => t.id.equals(id)))
          .write(const DoseLogsCompanion(pendingSync: Value(false)));

  // --- Pull/restore helpers ------------------------------------------------
  //
  // Used by SyncService.pullAll(). Medicines and schedules resolve by
  // last-write-wins on `updatedAt`; dose logs are append-only facts and stay
  // insert-or-ignore, since nothing ever edits one.

  /// `id -> updatedAt` for every local medicine, so a pull can decide which
  /// rows it needs to overwrite without a query per remote row.
  Future<Map<String, DateTime>> medicineVersions() async {
    final rows = await select(medicines).get();
    return {for (final r in rows) r.id: r.updatedAt};
  }

  /// `id -> updatedAt` for every local schedule. See [medicineVersions].
  Future<Map<String, DateTime>> scheduleVersions() async {
    final rows = await select(schedules).get();
    return {for (final r in rows) r.id: r.updatedAt};
  }

  /// Ids of every local dose log, so a pull can skip the ones it already has.
  Future<Set<String>> doseLogIds() async {
    final rows = await select(doseLogs).get();
    return {for (final r in rows) r.id};
  }

  /// Writes remote rows that won the version comparison, in one batch rather
  /// than a statement per row.
  Future<void> applyRemoteMedicines(List<MedicinesCompanion> rows) async {
    if (rows.isEmpty) return;
    await batch((b) => b.insertAllOnConflictUpdate(medicines, rows));
  }

  Future<void> applyRemoteSchedules(List<SchedulesCompanion> rows) async {
    if (rows.isEmpty) return;
    await batch((b) => b.insertAllOnConflictUpdate(schedules, rows));
  }

  Future<void> applyRemoteDoseLogs(List<DoseLogsCompanion> rows) async {
    if (rows.isEmpty) return;
    await batch((b) => b.insertAll(doseLogs, rows, mode: InsertMode.insertOrIgnore));
  }
}
