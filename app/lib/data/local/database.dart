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

@DriftDatabase(
  tables: [
    Medicines,
    Schedules,
    DoseLogs,
    DoseLogContests,
    TodayCareReminders,
    EmergencyInfo,
  ],
)
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
  int get schemaVersion => 12;

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
      if (from < 5) {
        await _storeDateTimesAsText(m);
      }
      if (from < 6) {
        // Phase 3 lifecycle metadata. All fields are nullable for a safe
        // upgrade: legacy rows continue to use `active`, while new writes
        // can distinguish paused and completed reminders and preserve their
        // course boundaries.
        // The v5 table-rebuild already uses the current table definition, so
        // databases crossing v4 -> v6 have these columns already. Only the
        // v5 -> v6 path needs ALTER TABLE additions.
        if (from >= 5) {
          await m.addColumn(schedules, schedules.status);
          await m.addColumn(schedules, schedules.startDate);
          await m.addColumn(schedules, schedules.endDate);
          await m.addColumn(schedules, schedules.pauseUntil);
        }
        await customStatement(
          "UPDATE schedules SET status = CASE WHEN frequency_type = 'asNeeded' THEN 'asNeeded' WHEN active = 1 THEN 'active' ELSE 'completed' END WHERE status IS NULL",
        );
      }
      if (from < 7) {
        await m.createTable(todayCareReminders);
      }
      if (from == 7) {
        await m.alterTable(
          TableMigration(
            todayCareReminders,
            newColumns: [
              todayCareReminders.updatedAt,
              todayCareReminders.pendingSync,
              todayCareReminders.deleted,
            ],
          ),
        );
      }
      if (from < 9) {
        // createTable builds from *today's* EmergencyInfo definition, so a
        // database created here already gets every column added below for
        // free. Only a database that already has the v9 table (from >= 9)
        // needs the ALTER TABLEs.
        await m.createTable(emergencyInfo);
      }
      if (from == 9) {
        // Idempotent: this app opens the same file from more than one
        // isolate (the main UI isolate and the notification/FCM background
        // isolate, see the AppDatabase doc comment below), and two of them
        // racing this migration on the same cold start can both decide they
        // need to run it. A plain addColumn crashes the second one with
        // "duplicate column name" -- which fails the whole database open,
        // for every screen, not just this table -- so check first.
        await _addColumnIfMissing(
          m,
          emergencyInfo,
          emergencyInfo.allergiesSevere,
        );
        await _addColumnIfMissing(m, emergencyInfo, emergencyInfo.notes);
        await _addColumnIfMissing(
          m,
          emergencyInfo,
          emergencyInfo.insuranceNumber,
        );
        await _addColumnIfMissing(m, emergencyInfo, emergencyInfo.nationalId);
        await _addColumnIfMissing(
          m,
          emergencyInfo,
          emergencyInfo.healthCardNumber,
        );
      }
      if (from >= 9 && from < 11) {
        // Covers both a v10 database and one jumping straight from v9 to
        // v11 in one upgrade -- same idempotency reasoning as above.
        await _addColumnIfMissing(
          m,
          emergencyInfo,
          emergencyInfo.emergencyContactName,
        );
        await _addColumnIfMissing(
          m,
          emergencyInfo,
          emergencyInfo.emergencyContactPhone,
        );
      }
      if (from < 12) {
        // See [Schedules.timingDefinedAt]'s doc comment. Existing rows have
        // never distinguished a timing edit from a cosmetic one, so the
        // honest backfill is the same value `wasArmed` already bounded on
        // before this column existed -- updatedAt -- which keeps every
        // schedule's missed-dose backfill behaving exactly as it did before
        // this migration. Uses the isolate-safe helper for the same reason
        // as the emergencyInfo columns above: two isolates can race this on
        // the same cold start.
        await _addColumnIfMissing(m, schedules, schedules.timingDefinedAt);
        await customStatement(
          'UPDATE schedules SET timing_defined_at = updated_at',
        );
      }
    },
  );

  /// Schema v4's DateTime columns were unix-seconds integers, truncating
  /// sub-second precision — two writes landing within the same second were
  /// indistinguishable, and one silently lost every future version
  /// comparison against the other. v5 stores them as ISO-8601 text instead
  /// (see build.yaml's `store_date_time_values_as_text`).
  ///
  /// SQLite cannot `ALTER ... SET DEFAULT`, so a column's default cannot be
  /// fixed in place — each table is recreated from [m]'s *current*
  /// definition instead, which already carries the right, text-mode default
  /// baked in, rather than one hand-written here that could drift from it.
  /// Every column this database has ever written a DateTime into holds a UTC
  /// instant (see SyncService.isoUtc and the `Value(DateTime.now())` call
  /// sites — none of them stamp a bare local time), so every conversion
  /// below produces the same `...Z`-suffixed text
  /// `SqlTypes.mapToSqlVariable` itself would write for a UTC value.
  Future<void> _storeDateTimesAsText(Migrator m) async {
    Future<void> convert({
      required TableInfo table,
      required String oldName,
      required List<String> plainColumns,
      required List<String> dateTimeColumns,
    }) async {
      await customStatement(
        'ALTER TABLE ${table.actualTableName} RENAME TO $oldName',
      );
      await m.createTable(table);
      final columnList = [...plainColumns, ...dateTimeColumns].join(', ');
      final selected = [
        ...plainColumns,
        for (final c in dateTimeColumns)
          "strftime('%Y-%m-%dT%H:%M:%S', $c, 'unixepoch') || '.000Z' AS $c",
      ].join(', ');
      await customStatement(
        'INSERT INTO ${table.actualTableName} ($columnList) '
        'SELECT $selected FROM $oldName',
      );
      await customStatement('DROP TABLE $oldName');
    }

    await convert(
      table: medicines,
      oldName: 'medicines_v4',
      plainColumns: [
        'id', 'drug_name', 'strength', 'form', 'dose_amount', //
        'tablets_remaining', 'tablets_per_dose', 'notes', 'updated_by',
        'pending_sync', 'deleted',
      ],
      dateTimeColumns: ['created_at', 'updated_at'],
    );
    await convert(
      table: schedules,
      oldName: 'schedules_v4',
      plainColumns: [
        'id', 'medicine_id', 'frequency_type', 'times', //
        'days_of_week', 'interval_hours', 'active', 'updated_by',
        'pending_sync', 'deleted',
      ],
      dateTimeColumns: ['created_at', 'updated_at'],
    );
    await convert(
      table: doseLogs,
      oldName: 'dose_logs_v4',
      plainColumns: ['id', 'schedule_id', 'action', 'source', 'pending_sync'],
      dateTimeColumns: ['scheduled_at', 'logged_at'],
    );
    await convert(
      table: doseLogContests,
      oldName: 'dose_log_contests_v4',
      plainColumns: ['dose_log_id', 'note', 'pending_sync'],
      dateTimeColumns: ['created_at', 'updated_at'],
    );
  }

  /// [Migrator.addColumn], but a no-op if the column is already there.
  /// SQLite's `ALTER TABLE ADD COLUMN` isn't idempotent on its own -- a
  /// second attempt throws "duplicate column name" -- and that's not just
  /// theoretical here: this app opens the same encrypted file from more
  /// than one isolate (see [AppDatabase]'s doc comment), so two isolates
  /// racing a cold start can both decide the same migration still needs to
  /// run.
  Future<void> _addColumnIfMissing(
    Migrator m,
    TableInfo table,
    GeneratedColumn column,
  ) async {
    final existing = await customSelect(
      "SELECT 1 FROM pragma_table_info('${table.actualTableName}') WHERE name = ?",
      variables: [Variable(column.name)],
    ).get();
    if (existing.isNotEmpty) return;
    await m.addColumn(table, column);
  }

  // --- Medicines ---------------------------------------------------------

  Future<void> upsertMedicine(MedicinesCompanion row) =>
      into(medicines).insertOnConflictUpdate(row);

  Future<Medicine?> medicineById(String id) =>
      (select(medicines)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Doses answered Taken on [scheduleId] strictly after [since] — the count
  /// [derivedTabletsRemaining] subtracts from a medicine's stored baseline.
  Future<int> takenCountSince(String scheduleId, DateTime since) async {
    final rows =
        await (select(doseLogs)..where(
              (t) =>
                  t.scheduleId.equals(scheduleId) &
                  t.action.equals(DoseAction.taken.name) &
                  t.loggedAt.isBiggerThanValue(since),
            ))
            .get();
    return rows.length;
  }

  /// [takenCountSince], batched across every schedule in [items] and summed
  /// per medicine — one medicine can have more than one active schedule, and
  /// every schedule against it draws from the same bottle.
  Future<Map<String, int>> takenCountsSinceBaseline(
    List<ScheduleWithMedicine> items,
  ) async {
    final out = <String, int>{};
    for (final item in items) {
      final n = await takenCountSince(
        item.schedule.id,
        item.medicine.updatedAt,
      );
      out[item.medicine.id] = (out[item.medicine.id] ?? 0) + n;
    }
    return out;
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
    final query = select(schedules).join(
      [innerJoin(medicines, medicines.id.equalsExp(schedules.medicineId))],
    )..where(schedules.deleted.equals(false) & medicines.deleted.equals(false));
    if (activeOnly) {
      query.where(
        schedules.active.equals(true) |
            (schedules.status.equals(ReminderStatus.paused.name) &
                schedules.pauseUntil.isSmallerOrEqualValue(DateTime.now())),
      );
    }
    return query.watch().map(
      (rows) => rows
          .map(
            (r) => ScheduleWithMedicine(
              r.readTable(schedules),
              r.readTable(medicines),
            ),
          )
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
    final query = select(schedules).join(
      [innerJoin(medicines, medicines.id.equalsExp(schedules.medicineId))],
    )..where(schedules.deleted.equals(false) & medicines.deleted.equals(false));
    if (activeOnly) {
      query.where(
        schedules.active.equals(true) |
            (schedules.status.equals(ReminderStatus.paused.name) &
                schedules.pauseUntil.isSmallerOrEqualValue(DateTime.now())),
      );
    }
    final rows = await query.get();
    return rows
        .map(
          (r) => ScheduleWithMedicine(
            r.readTable(schedules),
            r.readTable(medicines),
          ),
        )
        .toList();
  }

  Future<List<Schedule>> schedulesForMedicine(String medicineId) =>
      (select(schedules)..where((t) => t.medicineId.equals(medicineId))).get();

  /// Turning a reminder off is an edit like any other, so it has to carry a
  /// fresh [Schedules.updatedAt]. Without one it loses every version
  /// comparison against the server's still-active copy, and the reminder
  /// reappears on the next pull.
  ///
  /// It also bumps [Schedules.timingDefinedAt]. Deactivating changes what is
  /// expected going forward (nothing), and if this schedule is ever restarted
  /// via [resumeSchedule], [MissedDoseDetector.wasArmed] must not treat the
  /// dormant time in between as occurrences that were actually armed.
  Future<void> deactivateSchedule(String id, {String? by}) =>
      (update(schedules)..where((t) => t.id.equals(id))).write(
        SchedulesCompanion(
          active: const Value(false),
          status: const Value('completed'),
          pauseUntil: const Value(null),
          pendingSync: const Value(true),
          updatedAt: Value(DateTime.now()),
          timingDefinedAt: Value(DateTime.now()),
          updatedBy: Value(by),
        ),
      );

  Future<void> pauseSchedule(String id, {DateTime? until, String? by}) =>
      _setScheduleLifecycle(
        id,
        status: ReminderStatus.paused,
        active: false,
        pauseUntil: until,
        by: by,
      );

  Future<void> resumeSchedule(String id, {String? by}) => _setScheduleLifecycle(
    id,
    status: ReminderStatus.active,
    active: true,
    pauseUntil: null,
    by: by,
  );

  Future<void> completeSchedule(String id, {String? by}) =>
      _setScheduleLifecycle(
        id,
        status: ReminderStatus.completed,
        active: false,
        pauseUntil: null,
        by: by,
      );

  /// Also bumps [Schedules.timingDefinedAt], covering pause, resume, and
  /// complete (and, via [resumeSchedule], "Restart reminder" on a completed
  /// schedule). Each of these changes what is actually expected: a pause
  /// stops alarms from firing for a stretch, and `reminderStatus` auto-flips
  /// a paused schedule back to `active` once `pauseUntil` elapses — without
  /// re-anchoring here, the next [MissedDoseDetector.sweep] would see the
  /// schedule as active for the *entire* window it inspects (it only checks
  /// current status, not per-day historical status) and back-fill every
  /// paused day as a missed dose nobody could have answered. Anchoring at
  /// both pause and resume means only occurrences due after the resume (or
  /// restart) are ever eligible to be judged.
  Future<void> _setScheduleLifecycle(
    String id, {
    required ReminderStatus status,
    required bool active,
    required DateTime? pauseUntil,
    String? by,
  }) => (update(schedules)..where((t) => t.id.equals(id))).write(
    SchedulesCompanion(
      status: Value(status.name),
      active: Value(active),
      pauseUntil: Value(pauseUntil),
      pendingSync: const Value(true),
      updatedAt: Value(DateTime.now()),
      timingDefinedAt: Value(DateTime.now()),
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
        final logs = await (select(
          doseLogs,
        )..where((t) => t.scheduleId.isIn(scheduleIds))).get();
        final logIds = [for (final l in logs) l.id];
        if (logIds.isNotEmpty) {
          await (delete(
            doseLogContests,
          )..where((t) => t.doseLogId.isIn(logIds))).go();
        }
        await (delete(
          doseLogs,
        )..where((t) => t.scheduleId.isIn(scheduleIds))).go();
        await (update(
          schedules,
        )..where((t) => t.medicineId.equals(medicineId))).write(
          SchedulesCompanion(
            deleted: const Value(true),
            active: const Value(false),
            status: const Value('completed'),
            pauseUntil: const Value(null),
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
  /// backfill, or a test simulating a particular day — can say so instead.
  ///
  /// Stamped explicitly rather than left for the column default: repeated
  /// responses for one occurrence intentionally reuse the same deterministic
  /// id, so the conflict update also refreshes the response time and keeps the
  /// snooze window anchored to the latest tap.
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
        loggedAt: Value(loggedAt ?? DateTime.now()),
      ),
    );
  }

  Stream<List<DoseLog>> watchDoseLogsForSchedule(String scheduleId) =>
      (select(doseLogs)..where((t) => t.scheduleId.equals(scheduleId))).watch();

  /// Every local log. The calendar needs the whole retained window to paint
  /// month dots without a round-trip each time the visible month changes.
  Stream<List<DoseLog>> watchDoseLogs() => select(doseLogs).watch();

  Stream<List<DoseLogWithContest>> watchDoseLogsWithContests(
    String scheduleId,
  ) {
    final query = select(doseLogs).join([
      leftOuterJoin(
        doseLogContests,
        doseLogContests.doseLogId.equalsExp(doseLogs.id),
      ),
    ])..where(doseLogs.scheduleId.equals(scheduleId));
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

  Future<DoseLogContest?> contestForDoseLog(String doseLogId) => (select(
    doseLogContests,
  )..where((t) => t.doseLogId.equals(doseLogId))).getSingleOrNull();

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
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      return;
    }
    await (update(
      doseLogContests,
    )..where((t) => t.doseLogId.equals(doseLogId))).write(
      DoseLogContestsCompanion(
        note: Value(trimmed),
        updatedAt: Value(now),
        pendingSync: const Value(true),
      ),
    );
  }

  /// The emergency card's one row, if it has ever been filled in. Null
  /// (not an empty-fields row) until the first save, so the card and its
  /// edit screen can tell "never set up" from "set up with blanks."
  Stream<EmergencyInfoData?> watchEmergencyInfo() => (select(
    emergencyInfo,
  )..where((t) => t.id.equals(EmergencyInfo.singletonId))).watchSingleOrNull();

  Future<EmergencyInfoData?> emergencyInfoOnce() => (select(
    emergencyInfo,
  )..where((t) => t.id.equals(EmergencyInfo.singletonId))).getSingleOrNull();

  Future<void> upsertEmergencyInfo({
    required String bloodGroup,
    required String allergies,
    bool allergiesSevere = false,
    required String conditions,
    String notes = '',
    String insuranceNumber = '',
    String nationalId = '',
    String healthCardNumber = '',
    String emergencyContactName = '',
    String emergencyContactPhone = '',
  }) {
    return into(emergencyInfo).insertOnConflictUpdate(
      EmergencyInfoCompanion.insert(
        id: EmergencyInfo.singletonId,
        bloodGroup: Value(bloodGroup.trim()),
        allergies: Value(allergies.trim()),
        allergiesSevere: Value(allergiesSevere),
        conditions: Value(conditions.trim()),
        notes: Value(notes.trim()),
        insuranceNumber: Value(insuranceNumber.trim()),
        nationalId: Value(nationalId.trim()),
        healthCardNumber: Value(healthCardNumber.trim()),
        emergencyContactName: Value(emergencyContactName.trim()),
        emergencyContactPhone: Value(emergencyContactPhone.trim()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Most recent dose log for a schedule, if any. One-shot rather than
  /// reactive: the notification engine records Taken/Snooze from its own
  /// `AppDatabase` instance (often a different isolate entirely), and those
  /// writes don't push to a `.watch()` stream opened on this one — so
  /// callers that need this fresh must re-poll.
  Future<DoseLog?> latestDoseLogOnce(String scheduleId) =>
      (select(doseLogs)
            ..where((t) => t.scheduleId.equals(scheduleId))
            ..orderBy([(t) => OrderingTerm.desc(t.loggedAt)])
            ..limit(1))
          .getSingleOrNull();

  /// Every dose log written since [since], across all schedules — one query
  /// for a missed-dose sweep rather than one per reminder.
  Future<List<DoseLog>> doseLogsSince(DateTime since) => (select(
    doseLogs,
  )..where((t) => t.loggedAt.isBiggerOrEqualValue(since))).get();

  /// Logs whose [DoseLogs.scheduledAt] or [DoseLogs.loggedAt] falls in
  /// `[from, to)`. Used to paint a month: a late answer can carry a
  /// `scheduledAt` on another day, and matching only one column would
  /// leave that cell blank.
  Future<List<DoseLog>> doseLogsTouching(DateTime from, DateTime to) =>
      (select(doseLogs)..where(
            (t) =>
                (t.scheduledAt.isBiggerOrEqualValue(from) &
                    t.scheduledAt.isSmallerThanValue(to)) |
                (t.loggedAt.isBiggerOrEqualValue(from) &
                    t.loggedAt.isSmallerThanValue(to)),
          ))
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
  Future<List<String>> syncedMissedDoseIdsSince(
    DateTime since, {
    int limit = 200,
  }) async {
    final rows =
        await (select(doseLogs)
              ..where(
                (t) =>
                    t.action.equals(DoseAction.missed.name) &
                    t.pendingSync.equals(false) &
                    t.loggedAt.isBiggerOrEqualValue(since),
              )
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
  ///
  /// Deletes each expiring log's contest note with it. [DoseLogContests]
  /// declares `onDelete: cascade`, but nothing turns `PRAGMA foreign_keys`
  /// on for this database, so SQLite ignores every foreign key in the
  /// schema and the note would outlive the log it annotates — a free-text
  /// health note kept indefinitely, past the retention period the privacy
  /// policy states, and orphaned from the row that gives it meaning.
  /// [deleteMedicineAndHistory] already deletes contests explicitly for the
  /// same reason; this path did not.
  Future<int> pruneExpiredDoseLogs({DateTime? now}) async {
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
    return transaction(() async {
      final expiring = await (select(
        doseLogs,
      )..where((t) => t.loggedAt.isSmallerThanValue(cutoff))).get();
      if (expiring.isEmpty) return 0;
      final ids = [for (final log in expiring) log.id];
      await (delete(doseLogContests)..where((t) => t.doseLogId.isIn(ids))).go();
      return (delete(
        doseLogs,
      )..where((t) => t.loggedAt.isSmallerThanValue(cutoff))).go();
    });
  }

  /// Insert-or-ignore, because missed doses carry deterministic ids: a sweep
  /// that runs twice, or on a second device, must converge on the same row
  /// rather than filling the feed with duplicates of the same skipped dose.
  Future<void> recordMissedDoses(List<DoseLogsCompanion> rows) async {
    if (rows.isEmpty) return;
    await batch(
      (b) => b.insertAll(doseLogs, rows, mode: InsertMode.insertOrIgnore),
    );
  }

  // --- Sync helpers ----------------------------------------------------

  Future<List<Medicine>> unsyncedMedicines() =>
      (select(medicines)..where((t) => t.pendingSync.equals(true))).get();

  Future<List<TodayCareReminder>> unsyncedTodayCareReminders() => (select(
    todayCareReminders,
  )..where((t) => t.pendingSync.equals(true))).get();

  /// Compare inside the transaction: a local edit made while a request was
  /// in flight must not be overwritten or marked synced by its response.
  Future<void> applyRemoteTodayCareReminder(TodayCareReminder incoming) =>
      transaction(() async {
        final local = await (select(
          todayCareReminders,
        )..where((t) => t.id.equals(incoming.id))).getSingleOrNull();
        if (local != null && local.updatedAt.isAfter(incoming.updatedAt)) {
          return;
        }
        final clean = incoming.copyWith(pendingSync: false);
        if (local == clean) return;
        // A plain data class's toColumns drops null fields instead of
        // setting them, so a remote reminderMinutes: null would silently
        // keep a stale local value on conflict — toCompanion sends every
        // field explicitly, nulls included.
        await into(
          todayCareReminders,
        ).insertOnConflictUpdate(clean.toCompanion(false));
      });

  Future<List<Schedule>> unsyncedSchedules() =>
      (select(schedules)..where((t) => t.pendingSync.equals(true))).get();

  Future<List<DoseLog>> unsyncedDoseLogs() =>
      (select(doseLogs)..where((t) => t.pendingSync.equals(true))).get();

  Future<List<DoseLogContest>> unsyncedDoseLogContests() =>
      (select(doseLogContests)..where((t) => t.pendingSync.equals(true))).get();

  Future<void> markMedicineSynced(String id) =>
      (update(medicines)..where((t) => t.id.equals(id))).write(
        const MedicinesCompanion(pendingSync: Value(false)),
      );

  Future<void> markScheduleSynced(String id) =>
      (update(schedules)..where((t) => t.id.equals(id))).write(
        const SchedulesCompanion(pendingSync: Value(false)),
      );

  Future<void> markDoseLogSynced(String id) =>
      (update(doseLogs)..where((t) => t.id.equals(id))).write(
        const DoseLogsCompanion(pendingSync: Value(false)),
      );

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

  /// Local medicines missing from [remoteIds] that a pull may safely
  /// tombstone: rows this device believes are already synced, since a pull
  /// runs before push and there is nothing left here to lose. A `pendingSync`
  /// row is excluded — it might be a local edit or a brand-new medicine that
  /// simply hasn't reached the server yet, and this only ever runs against a
  /// SELECT that actually succeeded (the caller's try/catch sees to that), so
  /// its absence there is the server's word that this row is really gone.
  Future<List<String>> medicineIdsMissingRemotely(Set<String> remoteIds) async {
    final rows =
        await (select(medicines)..where(
              (t) => t.pendingSync.equals(false) & t.deleted.equals(false),
            ))
            .get();
    return [
      for (final r in rows)
        if (!remoteIds.contains(r.id)) r.id,
    ];
  }

  /// See [medicineIdsMissingRemotely].
  Future<List<String>> scheduleIdsMissingRemotely(Set<String> remoteIds) async {
    final rows =
        await (select(schedules)..where(
              (t) => t.pendingSync.equals(false) & t.deleted.equals(false),
            ))
            .get();
    return [
      for (final r in rows)
        if (!remoteIds.contains(r.id)) r.id,
    ];
  }

  /// Tombstones medicines a pull found gone from the server — the local half
  /// of a delete that happened on another device. Nothing to push back:
  /// the server already reflects this, so `pendingSync` stays false.
  Future<void> tombstoneMedicinesMissingRemotely(List<String> ids) async {
    if (ids.isEmpty) return;
    await (update(medicines)..where((t) => t.id.isIn(ids))).write(
      const MedicinesCompanion(deleted: Value(true), pendingSync: Value(false)),
    );
  }

  /// See [tombstoneMedicinesMissingRemotely].
  Future<void> tombstoneSchedulesMissingRemotely(List<String> ids) async {
    if (ids.isEmpty) return;
    await (update(schedules)..where((t) => t.id.isIn(ids))).write(
      const SchedulesCompanion(
        deleted: Value(true),
        active: Value(false),
        pendingSync: Value(false),
      ),
    );
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
    await batch(
      (b) => b.insertAll(doseLogs, accepted, mode: InsertMode.insertOrIgnore),
    );
  }

  Future<void> applyRemoteDoseLogContests(
    List<DoseLogContestsCompanion> rows,
  ) async {
    if (rows.isEmpty) return;
    await batch((b) => b.insertAllOnConflictUpdate(doseLogContests, rows));
  }

  Future<Set<String>> _deletedMedicineIds() async {
    final rows = await (select(
      medicines,
    )..where((t) => t.deleted.equals(true))).get();
    return {for (final r in rows) r.id};
  }

  Future<Set<String>> _deletedScheduleIds() async {
    final rows = await (select(
      schedules,
    )..where((t) => t.deleted.equals(true))).get();
    return {for (final r in rows) r.id};
  }

  /// Dose history for a locally deleted schedule, or for any schedule of a
  /// deleted medicine, must not come back from the server. Local dose logs
  /// were hard-deleted; insert-or-ignore would otherwise restore them.
  Future<Set<String>> _scheduleIdsHiddenFromRemoteDoseLogs() async {
    final deletedSchedules = await _deletedScheduleIds();
    final deletedMedicines = await _deletedMedicineIds();
    if (deletedMedicines.isEmpty) return deletedSchedules;
    final fromDeletedMedicines = await (select(
      schedules,
    )..where((t) => t.medicineId.isIn(deletedMedicines))).get();
    return {...deletedSchedules, for (final s in fromDeletedMedicines) s.id};
  }

  static String? _companionId(Value<String> id) => id.present ? id.value : null;

  static bool _isTombstoned(String? id, Set<String> tombstoned) =>
      id != null && tombstoned.contains(id);
}
