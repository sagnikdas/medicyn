import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'converters.dart';
import 'encrypted_database.dart';
import 'tables.dart';

part 'database.g.dart';

/// A row combining a schedule with its parent medicine — the shape most
/// screens (home list, notification engine) actually want.
class ScheduleWithMedicine {
  final Schedule schedule;
  final Medicine medicine;
  ScheduleWithMedicine(this.schedule, this.medicine);
}

/// A dose log plus the optional user correction note attached to it.
class DoseLogWithContest {
  final DoseLog log;
  final DoseLogContest? contest;
  DoseLogWithContest(this.log, this.contest);
}

@DriftDatabase(tables: [Medicines, Schedules, DoseLogs, DoseLogContests])
class AppDatabase extends _$AppDatabase {
  /// Opens the encrypted per-account file via [openEncryptedAppDatabase].
  /// Background isolates construct this the same way so Taken/Snooze and
  /// FCM pull hit the same key and the same file.
  AppDatabase() : super(openEncryptedAppDatabase());

  /// For tests: an isolated database with no file behind it, so logic that
  /// spans several tables can be exercised without a device. Unencrypted
  /// on purpose — tests never hold real medical rows.
  @visibleForTesting
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 4;

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
          if (from < 3) {
            await m.createTable(doseLogContests);
          }
          if (from < 4) {
            await m.addColumn(medicines, medicines.tabletsRemaining);
            await m.addColumn(medicines, medicines.tabletsPerDose);
          }
        },
      );

  // --- Medicines ---------------------------------------------------------

  Future<void> upsertMedicine(MedicinesCompanion row) =>
      into(medicines).insertOnConflictUpdate(row);

  Future<Medicine?> medicineById(String id) =>
      (select(medicines)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Subtracts one dose from the bottle for [scheduleId]'s medicine.
  ///
  /// Leaves [Medicines.updatedAt] alone: a Taken is not an edit of the
  /// reminder, and bumping the stamp would let a decrement overwrite a
  /// caregiver's concurrent change to the name.
  Future<void> decrementStockForSchedule(String scheduleId) async {
    final schedule = await scheduleById(scheduleId);
    if (schedule == null) return;
    final medicine = await medicineById(schedule.medicineId);
    if (medicine == null || medicine.tabletsRemaining == null) return;
    final perDose = (medicine.tabletsPerDose == null || medicine.tabletsPerDose! < 1)
        ? 1
        : medicine.tabletsPerDose!;
    final next = medicine.tabletsRemaining! - perDose;
    final remaining = next < 0 ? 0 : next;
    await (update(medicines)..where((t) => t.id.equals(medicine.id))).write(
      MedicinesCompanion(
        tabletsRemaining: Value(remaining),
        pendingSync: const Value(true),
      ),
    );
  }

  // --- Schedules -----------------------------------------------------------

  Future<void> upsertSchedule(SchedulesCompanion row) =>
      into(schedules).insertOnConflictUpdate(row);

  Future<Schedule?> scheduleById(String id) =>
      (select(schedules)..where((t) => t.id.equals(id))).getSingleOrNull();

  Stream<List<ScheduleWithMedicine>> watchActiveSchedules() =>
      watchSchedulesWithMedicines(activeOnly: true);

  /// Same join as [schedulesWithMedicinesOnce], live. The calendar watches
  /// inactive rows too, so a reminder that was stopped still paints its
  /// history.
  Stream<List<ScheduleWithMedicine>> watchSchedulesWithMedicines({
    bool activeOnly = false,
  }) {
    final query = select(schedules).join([
      innerJoin(medicines, medicines.id.equalsExp(schedules.medicineId)),
    ])
      ..where(schedules.deleted.equals(false) & medicines.deleted.equals(false));
    if (activeOnly) {
      query.where(schedules.active.equals(true));
    }
    return query.watch().map(
          (rows) => rows
              .map((r) => ScheduleWithMedicine(
                    r.readTable(schedules),
                    r.readTable(medicines),
                  ))
              .toList(),
        );
  }

  Future<List<ScheduleWithMedicine>> activeSchedulesOnce() =>
      schedulesWithMedicinesOnce(activeOnly: true);

  /// Active and inactive, excluding deleted medicines/schedules.
  ///
  /// The calendar has to paint history for a reminder that was turned off,
  /// so the default includes inactive rows. [activeOnly] keeps the alarm
  /// and home-list filter without a second join.
  Future<List<ScheduleWithMedicine>> schedulesWithMedicinesOnce({
    bool activeOnly = false,
  }) async {
    final query = select(schedules).join([
      innerJoin(medicines, medicines.id.equalsExp(schedules.medicineId)),
    ])
      ..where(schedules.deleted.equals(false) & medicines.deleted.equals(false));
    if (activeOnly) {
      query.where(schedules.active.equals(true));
    }
    final rows = await query.get();
    return rows
        .map((r) => ScheduleWithMedicine(
              r.readTable(schedules),
              r.readTable(medicines),
            ))
        .toList();
  }

  Future<List<Schedule>> schedulesForMedicine(String medicineId) =>
      (select(schedules)..where((t) => t.medicineId.equals(medicineId))).get();

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

  /// Removes this medicine's dose history and tombstones the medicine and its
  /// schedules. The rows stay locally with [Medicines.deleted] /
  /// [Schedules.deleted] set so a later pull cannot resurrect them before the
  /// server `DELETE` lands. Dose logs are hard-deleted: history must actually
  /// go, and there is no tombstone column on that table.
  Future<void> deleteMedicineAndHistory(String medicineId, {String? by}) async {
    final now = DateTime.now();
    final related = await schedulesForMedicine(medicineId);
    final scheduleIds = [for (final s in related) s.id];
    await transaction(() async {
      if (scheduleIds.isNotEmpty) {
        final logs = await (select(doseLogs)
              ..where((t) => t.scheduleId.isIn(scheduleIds)))
            .get();
        final logIds = [for (final l in logs) l.id];
        if (logIds.isNotEmpty) {
          await (delete(doseLogContests)..where((t) => t.doseLogId.isIn(logIds))).go();
        }
        await (delete(doseLogs)..where((t) => t.scheduleId.isIn(scheduleIds))).go();
        await (update(schedules)..where((t) => t.medicineId.equals(medicineId))).write(
          SchedulesCompanion(
            deleted: const Value(true),
            active: const Value(false),
            pendingSync: const Value(true),
            updatedAt: Value(now),
            updatedBy: Value(by),
          ),
        );
      }
      await (update(medicines)..where((t) => t.id.equals(medicineId))).write(
        MedicinesCompanion(
          deleted: const Value(true),
          pendingSync: const Value(true),
          updatedAt: Value(now),
          updatedBy: Value(by),
        ),
      );
    });
  }

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

  /// Every local log. The calendar needs the whole retained window to paint
  /// month dots without a round-trip each time the visible month changes.
  Stream<List<DoseLog>> watchDoseLogs() => select(doseLogs).watch();

  Stream<List<DoseLogWithContest>> watchDoseLogsWithContests(String scheduleId) {
    final query = select(doseLogs).join([
      leftOuterJoin(
        doseLogContests,
        doseLogContests.doseLogId.equalsExp(doseLogs.id),
      ),
    ])
      ..where(doseLogs.scheduleId.equals(scheduleId));
    return query.watch().map(
          (rows) => rows
              .map(
                (r) => DoseLogWithContest(
                  r.readTable(doseLogs),
                  r.readTableOrNull(doseLogContests),
                ),
              )
              .toList(),
        );
  }

  Future<DoseLog?> doseLogById(String id) =>
      (select(doseLogs)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<DoseLogContest?> contestForDoseLog(String doseLogId) =>
      (select(doseLogContests)..where((t) => t.doseLogId.equals(doseLogId)))
          .getSingleOrNull();

  /// Attaches or replaces the correction note. Does not touch the log row.
  Future<void> upsertDoseLogContest({
    required String doseLogId,
    required String note,
  }) async {
    final trimmed = note.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(note, 'note', 'must not be empty');
    }
    final existing = await contestForDoseLog(doseLogId);
    final now = DateTime.now();
    if (existing == null) {
      await into(doseLogContests).insert(
        DoseLogContestsCompanion.insert(
          doseLogId: doseLogId,
          note: trimmed,
        ),
      );
      return;
    }
    await (update(doseLogContests)..where((t) => t.doseLogId.equals(doseLogId)))
        .write(
      DoseLogContestsCompanion(
        note: Value(trimmed),
        updatedAt: Value(now),
        pendingSync: const Value(true),
      ),
    );
  }

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

  /// Logs whose [DoseLogs.scheduledAt] or [DoseLogs.loggedAt] falls in
  /// `[from, to)`. Used to paint a month: a late answer can carry a
  /// `scheduledAt` on another day, and matching only one column would
  /// leave that cell blank.
  Future<List<DoseLog>> doseLogsTouching(DateTime from, DateTime to) =>
      (select(doseLogs)
            ..where((t) =>
                (t.scheduledAt.isBiggerOrEqualValue(from) &
                    t.scheduledAt.isSmallerThanValue(to)) |
                (t.loggedAt.isBiggerOrEqualValue(from) &
                    t.loggedAt.isSmallerThanValue(to))))
          .get();

  /// Ids of missed doses recorded since [since] that are known to be on the
  /// server.
  ///
  /// This is what the caregiver's alert is raised from, and it is deliberately
  /// a question about *state* rather than about what a particular sync call
  /// happened to push. Deriving it from one call's result ties the alert to
  /// that call succeeding end to end: an upsert that commits server-side but
  /// whose response never arrives — a timeout, a dropped connection, the app
  /// being killed — leaves the dose in Postgres and the alert lost for good,
  /// silently. Asking the database instead means the next foreground simply
  /// asks again, and `care_alerts`' unique index makes saying it twice free.
  ///
  /// Synced rows only: the notification's wording is composed server-side from
  /// these rows, so naming one that is still on this phone alone would have the
  /// server find nothing to talk about.
  ///
  /// Newest first and capped, so a phone returning from a long absence sends a
  /// bounded request rather than every dose in the lookback window.
  Future<List<String>> syncedMissedDoseIdsSince(DateTime since, {int limit = 200}) async {
    final rows = await (select(doseLogs)
          ..where((t) =>
              t.action.equals(DoseAction.missed.name) &
              t.pendingSync.equals(false) &
              t.loggedAt.isBiggerOrEqualValue(since))
          ..orderBy([(t) => OrderingTerm.desc(t.loggedAt)])
          ..limit(limit))
        .get();
    return [for (final r in rows) r.id];
  }

  /// Drops local dose history older than 24 months, matching the server
  /// retention period. [now] is for tests that need a frozen clock.
  ///
  /// Calendar months, not 730 days, so this agrees with Postgres
  /// `logged_at < now() - interval '24 months'`.
  Future<int> pruneExpiredDoseLogs({DateTime? now}) {
    final clock = now ?? DateTime.now();
    final cutoff = DateTime(
      clock.year - 2,
      clock.month,
      clock.day,
      clock.hour,
      clock.minute,
      clock.second,
      clock.millisecond,
      clock.microsecond,
    );
    return (delete(doseLogs)..where((t) => t.loggedAt.isSmallerThanValue(cutoff))).go();
  }

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

  Future<List<DoseLogContest>> unsyncedDoseLogContests() =>
      (select(doseLogContests)..where((t) => t.pendingSync.equals(true))).get();

  Future<void> markMedicineSynced(String id) =>
      (update(medicines)..where((t) => t.id.equals(id)))
          .write(const MedicinesCompanion(pendingSync: Value(false)));

  Future<void> markScheduleSynced(String id) =>
      (update(schedules)..where((t) => t.id.equals(id)))
          .write(const SchedulesCompanion(pendingSync: Value(false)));

  Future<void> markDoseLogSynced(String id) =>
      (update(doseLogs)..where((t) => t.id.equals(id)))
          .write(const DoseLogsCompanion(pendingSync: Value(false)));

  Future<void> markDoseLogContestSynced(String doseLogId) =>
      (update(doseLogContests)..where((t) => t.doseLogId.equals(doseLogId)))
          .write(const DoseLogContestsCompanion(pendingSync: Value(false)));

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
  ///
  /// Projects the id column rather than selecting whole rows: this is the
  /// largest table by far, and reading every column of two years of history
  /// to throw all but one of them away cost the pull an order of magnitude
  /// more than it needed to.
  Future<Set<String>> doseLogIds() async {
    final query = selectOnly(doseLogs)..addColumns([doseLogs.id]);
    final rows = await query.get();
    return {for (final r in rows) r.read(doseLogs.id)!};
  }

  /// `doseLogId -> updatedAt` for every local contest note. Unlike dose logs,
  /// these rows are editable, so a pull has to version-compare them.
  Future<Map<String, DateTime>> doseLogContestVersions() async {
    final rows = await select(doseLogContests).get();
    return {for (final r in rows) r.doseLogId: r.updatedAt};
  }

  /// Writes remote rows that won the version comparison, in one batch rather
  /// than a statement per row. A local tombstone is never overwritten: pull
  /// runs before push on cold start, and restoring the pre-delete server copy
  /// would put a "removed" medicine back on this phone.
  Future<void> applyRemoteMedicines(List<MedicinesCompanion> rows) async {
    if (rows.isEmpty) return;
    final tombstoned = await _deletedMedicineIds();
    final accepted = [
      for (final row in rows)
        if (!_isTombstoned(_companionId(row.id), tombstoned)) row,
    ];
    if (accepted.isEmpty) return;
    await batch((b) => b.insertAllOnConflictUpdate(medicines, accepted));
  }

  Future<void> applyRemoteSchedules(List<SchedulesCompanion> rows) async {
    if (rows.isEmpty) return;
    final tombstonedSchedules = await _deletedScheduleIds();
    final tombstonedMedicines = await _deletedMedicineIds();
    final accepted = <SchedulesCompanion>[];
    for (final row in rows) {
      if (_isTombstoned(_companionId(row.id), tombstonedSchedules)) continue;
      if (_isTombstoned(_companionId(row.medicineId), tombstonedMedicines)) {
        continue;
      }
      accepted.add(row);
    }
    if (accepted.isEmpty) return;
    await batch((b) => b.insertAllOnConflictUpdate(schedules, accepted));
  }

  Future<void> applyRemoteDoseLogs(List<DoseLogsCompanion> rows) async {
    if (rows.isEmpty) return;
    final blocked = await _scheduleIdsHiddenFromRemoteDoseLogs();
    final accepted = [
      for (final row in rows)
        if (!_isTombstoned(_companionId(row.scheduleId), blocked)) row,
    ];
    if (accepted.isEmpty) return;
    await batch((b) => b.insertAll(doseLogs, accepted, mode: InsertMode.insertOrIgnore));
  }

  Future<void> applyRemoteDoseLogContests(List<DoseLogContestsCompanion> rows) async {
    if (rows.isEmpty) return;
    await batch((b) => b.insertAllOnConflictUpdate(doseLogContests, rows));
  }

  Future<Set<String>> _deletedMedicineIds() async {
    final rows = await (select(medicines)..where((t) => t.deleted.equals(true))).get();
    return {for (final r in rows) r.id};
  }

  Future<Set<String>> _deletedScheduleIds() async {
    final rows = await (select(schedules)..where((t) => t.deleted.equals(true))).get();
    return {for (final r in rows) r.id};
  }

  /// Dose history for a locally deleted schedule, or for any schedule of a
  /// deleted medicine, must not come back from the server. Local dose logs
  /// were hard-deleted; insert-or-ignore would otherwise restore them.
  Future<Set<String>> _scheduleIdsHiddenFromRemoteDoseLogs() async {
    final deletedSchedules = await _deletedScheduleIds();
    final deletedMedicines = await _deletedMedicineIds();
    if (deletedMedicines.isEmpty) return deletedSchedules;
    final fromDeletedMedicines =
        await (select(schedules)..where((t) => t.medicineId.isIn(deletedMedicines))).get();
    return {
      ...deletedSchedules,
      for (final s in fromDeletedMedicines) s.id,
    };
  }

  static String? _companionId(Value<String> id) => id.present ? id.value : null;

  static bool _isTombstoned(String? id, Set<String> tombstoned) =>
      id != null && tombstoned.contains(id);
}
