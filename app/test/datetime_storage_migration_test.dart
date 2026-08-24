import 'package:dosely/data/local/database.dart';
import 'package:dosely/data/local/tables.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers the last of PR #68's deferred findings: DateTime columns stored
/// as unix-seconds integers, truncating sub-second precision — two writes
/// landing in the same second were indistinguishable, and one silently lost
/// every future version comparison.
///
/// Fixed by turning on `store_date_time_values_as_text` (see build.yaml) and
/// migrating every existing schema-v4 database to match on upgrade
/// (`AppDatabase._storeDateTimesAsText`). These tests seed a raw v4-shaped
/// database by hand — the same shape a real device upgrading from before
/// this change would have on disk — and open it through the real
/// `AppDatabase` migration path, the same one a device actually runs.
void main() {
  const medicineId = 'm1';
  const scheduleId = 's1';
  const doseLogId = 'log1';

  /// Whole seconds only, matching the old storage's truncation — this is
  /// what makes the regression this migration fixes reproducible: a value
  /// with real sub-second precision was never representable in v4 to begin
  /// with, so seeding one here would test something no real database ever
  /// actually held.
  final createdAtSeconds = DateTime.utc(2026, 8, 1, 9, 0, 0);
  final updatedAtSeconds = DateTime.utc(2026, 8, 20, 11, 30, 0);

  int unix(DateTime dt) => dt.millisecondsSinceEpoch ~/ 1000;

  /// Builds an in-memory database shaped exactly like a real device's would
  /// be right before this migration: schema version 4, DateTime columns as
  /// unix-seconds integers, seeded with one row per table.
  QueryExecutor seedV4Database() {
    return NativeDatabase.memory(
      setup: (rawDb) {
        rawDb.execute('''
          CREATE TABLE medicines (
            id TEXT NOT NULL PRIMARY KEY,
            drug_name TEXT NOT NULL,
            strength TEXT NOT NULL DEFAULT '',
            form TEXT NOT NULL DEFAULT '',
            dose_amount TEXT NOT NULL DEFAULT '',
            tablets_remaining INTEGER NULL,
            tablets_per_dose INTEGER NULL,
            notes TEXT NOT NULL DEFAULT '',
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            updated_by TEXT NULL,
            pending_sync INTEGER NOT NULL DEFAULT 1,
            deleted INTEGER NOT NULL DEFAULT 0
          );
          CREATE TABLE schedules (
            id TEXT NOT NULL PRIMARY KEY,
            medicine_id TEXT NOT NULL,
            frequency_type TEXT NOT NULL,
            times TEXT NOT NULL,
            days_of_week TEXT NOT NULL DEFAULT '[]',
            interval_hours INTEGER NULL,
            active INTEGER NOT NULL DEFAULT 1,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            updated_by TEXT NULL,
            pending_sync INTEGER NOT NULL DEFAULT 1,
            deleted INTEGER NOT NULL DEFAULT 0
          );
          CREATE TABLE dose_logs (
            id TEXT NOT NULL PRIMARY KEY,
            schedule_id TEXT NOT NULL,
            scheduled_at INTEGER NOT NULL,
            action TEXT NOT NULL,
            logged_at INTEGER NOT NULL,
            source TEXT NOT NULL DEFAULT 'notification',
            pending_sync INTEGER NOT NULL DEFAULT 1
          );
          CREATE TABLE dose_log_contests (
            dose_log_id TEXT NOT NULL PRIMARY KEY,
            note TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            pending_sync INTEGER NOT NULL DEFAULT 1
          );
        ''');
        rawDb.execute('''
          INSERT INTO medicines
            (id, drug_name, strength, tablets_remaining, tablets_per_dose, created_at, updated_at, updated_by, pending_sync, deleted)
          VALUES
            ('$medicineId', 'Metformin', '500mg', 30, 1, ${unix(createdAtSeconds)}, ${unix(updatedAtSeconds)}, 'user-1', 0, 0);
        ''');
        rawDb.execute('''
          INSERT INTO schedules
            (id, medicine_id, frequency_type, times, created_at, updated_at, pending_sync)
          VALUES
            ('$scheduleId', '$medicineId', 'daily', '["09:00"]', ${unix(createdAtSeconds)}, ${unix(updatedAtSeconds)}, 0);
        ''');
        rawDb.execute('''
          INSERT INTO dose_logs
            (id, schedule_id, scheduled_at, action, logged_at, pending_sync)
          VALUES
            ('$doseLogId', '$scheduleId', ${unix(createdAtSeconds)}, 'taken', ${unix(updatedAtSeconds)}, 0);
        ''');
        rawDb.execute('''
          INSERT INTO dose_log_contests
            (dose_log_id, note, created_at, updated_at, pending_sync)
          VALUES
            ('$doseLogId', 'Actually took it at noon', ${unix(createdAtSeconds)}, ${unix(updatedAtSeconds)}, 0);
        ''');
        rawDb.execute('PRAGMA user_version = 4');
      },
    );
  }

  test('an upgraded v4 database reads every DateTime column correctly', () async {
    final db = AppDatabase.forTesting(seedV4Database());
    addTearDown(db.close);

    final medicine = await db.medicineById(medicineId);
    expect(medicine, isNotNull);
    expect(medicine!.createdAt, createdAtSeconds);
    expect(medicine.updatedAt, updatedAtSeconds);
    expect(medicine.drugName, 'Metformin');
    expect(medicine.tabletsRemaining, 30);

    final schedule = await db.scheduleById(scheduleId);
    expect(schedule, isNotNull);
    expect(schedule!.createdAt, createdAtSeconds);
    expect(schedule.updatedAt, updatedAtSeconds);

    final log = await db.doseLogById(doseLogId);
    expect(log, isNotNull);
    expect(log!.scheduledAt, createdAtSeconds);
    expect(log.loggedAt, updatedAtSeconds);

    final contest = await db.contestForDoseLog(doseLogId);
    expect(contest, isNotNull);
    expect(contest!.createdAt, createdAtSeconds);
    expect(contest.updatedAt, updatedAtSeconds);
    expect(contest.note, 'Actually took it at noon');
  });

  test('a new write after the upgrade round-trips sub-second precision', () async {
    final db = AppDatabase.forTesting(seedV4Database());
    addTearDown(db.close);

    // The whole point of the migration: this is representable now, and
    // wasn't in v4 — see createdAtSeconds/updatedAtSeconds above.
    final precise = DateTime.utc(2026, 8, 21, 10, 0, 0, 437);
    await db.recordDoseAction(
      id: 'log2',
      scheduleId: scheduleId,
      scheduledAt: precise,
      action: DoseAction.taken,
      loggedAt: precise,
    );

    final log = await db.doseLogById('log2');
    expect(log!.loggedAt, precise);
    expect(log.loggedAt.millisecond, 437);
  });

  test('the underlying storage is genuinely text, not a truncated integer', () async {
    final db = AppDatabase.forTesting(seedV4Database());
    addTearDown(db.close);

    final raw = await db.customSelect(
      'SELECT created_at FROM medicines WHERE id = ?',
      variables: [Variable.withString(medicineId)],
    ).getSingle();
    final stored = raw.data['created_at'];
    expect(stored, isA<String>());
    expect(stored, endsWith('Z'));
  });
}
