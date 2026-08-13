import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

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

  @override
  int get schemaVersion => 1;

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

  Future<void> deactivateSchedule(String id) =>
      (update(schedules)..where((t) => t.id.equals(id))).write(
        SchedulesCompanion(active: const Value(false), pendingSync: const Value(true)),
      );

  // --- Dose logs -----------------------------------------------------------

  Future<void> recordDoseAction({
    required String id,
    required String scheduleId,
    required DateTime scheduledAt,
    required DoseAction action,
    String source = 'notification',
  }) {
    return into(doseLogs).insertOnConflictUpdate(
      DoseLogsCompanion.insert(
        id: id,
        scheduleId: scheduleId,
        scheduledAt: scheduledAt,
        action: action.name,
        source: Value(source),
      ),
    );
  }

  Stream<List<DoseLog>> watchDoseLogsForSchedule(String scheduleId) =>
      (select(doseLogs)..where((t) => t.scheduleId.equals(scheduleId))).watch();

  /// One-shot (not reactive) read — safe to call after a write made by a
  /// different `AppDatabase` instance/isolate (e.g. the notification action
  /// handler), whose writes a `.watch()` stream on this instance won't push.
  Future<List<DoseLog>> doseLogsForScheduleOnce(String scheduleId) =>
      (select(doseLogs)..where((t) => t.scheduleId.equals(scheduleId))).get();

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
}
