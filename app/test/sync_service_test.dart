import 'package:dosely/core/app_settings.dart';
import 'package:dosely/data/local/database.dart';
import 'package:dosely/data/local/tables.dart';
import 'package:dosely/data/remote/sync_service.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_supabase.dart';

/// Drives the real [SyncService] against a stubbed PostgREST transport, so
/// the merge rules, the tombstone rules and the retry bookkeeping are
/// exercised as written rather than reimplemented in a fake.
///
/// What matters here is that nothing is silently lost and nothing silently
/// comes back: this is a shared medical record, and a wrong merge tells a
/// family something untrue about whether a tablet was taken.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userId = '11111111-1111-1111-1111-111111111111';
  final backend = FakePostgrest();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await initFakeSupabase(backend: backend, userId: userId);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AppSettings.instance.resetForTest();
    await AppSettings.instance.init();
    // Consents are account-scoped; use the local owner fixture explicitly so
    // each test starts from a fresh, granted backup choice.
    await AppSettings.instance.setConsentCloudBackup(true);
    backend.tables.clear();
    backend.requests.clear();
    backend.failing.clear();
    backend.hanging.clear();
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  Future<void> seedLocalMedicine({
    String id = 'med-1',
    String name = 'Metformin',
    DateTime? updatedAt,
    bool deleted = false,
    bool pendingSync = true,
  }) =>
      db.upsertMedicine(MedicinesCompanion.insert(
        id: id,
        drugName: name,
        updatedAt: Value(updatedAt ?? DateTime(2026, 8, 1)),
        deleted: Value(deleted),
        pendingSync: Value(pendingSync),
      ));

  Future<void> seedLocalSchedule({
    String id = 'sched-1',
    String medicineId = 'med-1',
    bool pendingSync = true,
    DateTime? updatedAt,
    bool deleted = false,
  }) =>
      db.upsertSchedule(SchedulesCompanion.insert(
        id: id,
        medicineId: medicineId,
        frequencyType: 'daily',
        times: const <String>['08:00'],
        daysOfWeek: const Value(<int>[]),
        updatedAt: Value(updatedAt ?? DateTime(2026, 8, 1)),
        pendingSync: Value(pendingSync),
        deleted: Value(deleted),
      ));

  Map<String, dynamic> remoteMedicine({
    String id = 'med-1',
    String name = 'Metformin',
    String updatedAt = '2026-08-10T00:00:00Z',
  }) =>
      {
        'id': id,
        'user_id': userId,
        'drug_name': name,
        'strength': '500mg',
        'form': 'tablet',
        'dose_amount': '1 tablet',
        'notes': '',
        'tablets_remaining': 30,
        'tablets_per_dose': 1,
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': updatedAt,
        'updated_by': 'caregiver',
      };

  Map<String, dynamic> remoteSchedule({
    String id = 'sched-1',
    String medicineId = 'med-1',
    String frequency = 'daily',
    List<String> times = const ['09:00'],
    List<int> days = const [],
    int? interval,
    String updatedAt = '2026-08-10T00:00:00Z',
  }) =>
      {
        'id': id,
        'medicine_id': medicineId,
        'user_id': userId,
        'frequency_type': frequency,
        'times': times,
        'days_of_week': days,
        'interval_hours': interval,
        'active': true,
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': updatedAt,
        'updated_by': 'caregiver',
      };

  Map<String, dynamic> remoteDoseLog({
    String id = 'log-1',
    String scheduleId = 'sched-1',
    String action = 'taken',
    String? source = 'notification',
  }) =>
      {
        'id': id,
        'schedule_id': scheduleId,
        'user_id': userId,
        'scheduled_at': '2026-08-10T08:00:00Z',
        'action': action,
        'logged_at': '2026-08-10T08:05:00Z',
        'source': source,
      };

  group('consent gates the network entirely', () {
    test('no request is made when cloud backup is off', () async {
      SharedPreferences.setMockInitialValues({'consent_cloud_backup': false});
      AppSettings.instance.resetForTest();
      await AppSettings.instance.init();
      await AppSettings.instance.setConsentCloudBackup(false);
      await seedLocalMedicine();

      await SyncService(db).syncAll();
      await SyncService(db).pullAll();

      expect(backend.requests, isEmpty);
      expect((await db.unsyncedMedicines()), hasLength(1),
          reason: 'the row stays dirty, ready for when consent is given');
    });
  });

  group('push', () {
    test('sends a dirty medicine and marks it clean', () async {
      await seedLocalMedicine();

      await SyncService(db).syncAll();

      final write = backend.lastWriteTo('medicines')!;
      expect(write.rows.single['drug_name'], 'Metformin');
      expect(write.rows.single['user_id'], userId);
      expect(await db.unsyncedMedicines(), isEmpty);
    });

    test('stamps every client time as UTC, with the offset attached', () async {
      await seedLocalMedicine(updatedAt: DateTime(2026, 8, 1, 9, 30));

      await SyncService(db).syncAll();

      final sent = backend.lastWriteTo('medicines')!.rows.single;
      expect(sent['updated_at'], endsWith('Z'));
      expect(
        DateTime.parse(sent['updated_at'] as String).toUtc(),
        DateTime(2026, 8, 1, 9, 30).toUtc(),
        reason: 'a bare local timestamp would be read by Postgres as UTC',
      );
    });

    test('a tombstone is a DELETE, never an upsert', () async {
      await seedLocalMedicine(deleted: true);

      await SyncService(db).syncAll();

      final writes = backend.writesTo('medicines').toList();
      expect(writes.map((w) => w.method), contains('DELETE'));
      expect(writes.where((w) => w.method == 'POST'), isEmpty);
      expect(await db.unsyncedMedicines(), isEmpty);
    });

    test('a failed push leaves the row dirty so the next pass retries',
        () async {
      await seedLocalMedicine();
      backend.failing.add('medicines');

      await SyncService(db).syncAll();

      expect(await db.unsyncedMedicines(), hasLength(1));
    });

    test('one table failing does not stop the others syncing', () async {
      await seedLocalMedicine();
      await seedLocalSchedule();
      backend.failing.add('medicines');

      await SyncService(db).syncAll();

      expect(await db.unsyncedMedicines(), hasLength(1));
      expect(await db.unsyncedSchedules(), isEmpty,
          reason: 'a schedule must still reach the caregiver');
    });

    test('pushedEdits marks a reminder change, not a dose being recorded',
        () async {
      await seedLocalMedicine();
      final withEdit = SyncService(db);
      await withEdit.syncAll();
      expect(withEdit.pushedEdits, isTrue);

      await db.recordDoseAction(
        id: 'log-local',
        scheduleId: 'sched-1',
        scheduledAt: DateTime(2026, 8, 10, 8),
        action: DoseAction.taken,
      );
      final logOnly = SyncService(db);
      await logOnly.syncAll();
      expect(logOnly.pushedEdits, isFalse,
          reason: 'a Taken must not trigger the silent re-arm push');
    });

    test('nothing dirty means no request at all', () async {
      await seedLocalMedicine(pendingSync: false);

      await SyncService(db).syncAll();

      expect(backend.writesTo('medicines'), isEmpty);
    });
  });

  group('pull merges by last-write-wins', () {
    test('a strictly newer remote edit replaces the local copy', () async {
      await seedLocalMedicine(name: 'Metformin', updatedAt: DateTime.utc(2026, 8, 1));
      backend.tables['medicines'] = [
        remoteMedicine(name: 'Metformin XR', updatedAt: '2026-08-10T00:00:00Z'),
      ];

      await SyncService(db).pullAll();

      expect((await db.medicineById('med-1'))!.drugName, 'Metformin XR');
    });

    test('an older remote edit does not clobber a newer local one', () async {
      await seedLocalMedicine(name: 'Local name', updatedAt: DateTime.utc(2026, 8, 20));
      backend.tables['medicines'] = [
        remoteMedicine(name: 'Stale', updatedAt: '2026-08-10T00:00:00Z'),
      ];

      await SyncService(db).pullAll();

      expect((await db.medicineById('med-1'))!.drugName, 'Local name');
    });

    test('equal timestamps leave the row alone', () async {
      await seedLocalMedicine(name: 'Local name', updatedAt: DateTime.utc(2026, 8, 10));
      backend.tables['medicines'] = [
        remoteMedicine(name: 'Same age', updatedAt: '2026-08-10T00:00:00Z'),
      ];

      await SyncService(db).pullAll();

      expect((await db.medicineById('med-1'))!.drugName, 'Local name');
    });

    test('a pulled row is not marked dirty, so it cannot bounce back',
        () async {
      backend.tables['medicines'] = [remoteMedicine()];

      await SyncService(db).pullAll();

      expect(await db.unsyncedMedicines(), isEmpty);
    });
  });

  group('pull never resurrects what this device deleted', () {
    test('a locally deleted medicine stays deleted', () async {
      await seedLocalMedicine(deleted: true, pendingSync: false);
      backend.tables['medicines'] = [remoteMedicine(name: 'Back from the dead')];

      await SyncService(db).pullAll();

      expect((await db.medicineById('med-1'))!.deleted, isTrue);
      expect((await db.medicineById('med-1'))!.drugName, 'Metformin');
    });

    test('a schedule belonging to a deleted medicine is not restored',
        () async {
      await seedLocalMedicine(deleted: true, pendingSync: false);
      backend.tables['schedules'] = [remoteSchedule()];

      await SyncService(db).pullAll();

      expect(await db.scheduleById('sched-1'), isNull);
    });

    test('dose history for a deleted medicine does not come back', () async {
      await seedLocalMedicine(deleted: true, pendingSync: false);
      await seedLocalSchedule(pendingSync: false);
      backend.tables['dose_logs'] = [remoteDoseLog()];

      await SyncService(db).pullAll();

      expect(await db.doseLogById('log-1'), isNull);
    });
  });

  group('pull refuses a schedule it could not arm', () {
    test('a zero interval is rejected and the local copy kept', () async {
      await seedLocalSchedule(pendingSync: false);
      backend.tables['schedules'] = [
        remoteSchedule(frequency: 'everyXHours', interval: 0),
      ];

      final sync = SyncService(db);
      await sync.pullAll();

      expect((await db.scheduleById('sched-1'))!.times, ['08:00'],
          reason: 'the working local schedule must survive a bad remote one');
      expect(sync.rejectedScheduleIds, contains('sched-1'));
    });

    test('an unknown frequency is rejected', () async {
      backend.tables['schedules'] = [remoteSchedule(frequency: 'hourly')];

      final sync = SyncService(db);
      await sync.pullAll();

      expect(await db.scheduleById('sched-1'), isNull);
      expect(sync.rejectedScheduleIds, contains('sched-1'));
    });

    test('a salvageable row is cleaned rather than dropped', () async {
      backend.tables['schedules'] = [
        remoteSchedule(times: const ['09:00', '25:00'], days: const [1, 9]),
      ];

      await SyncService(db).pullAll();

      final stored = (await db.scheduleById('sched-1'))!;
      expect(stored.times, ['09:00']);
      expect(stored.daysOfWeek, [1]);
    });

    test('schedulesChanged tells the caller the armed alarms are stale',
        () async {
      backend.tables['schedules'] = [remoteSchedule()];
      final sync = SyncService(db);
      await sync.pullAll();
      expect(sync.schedulesChanged, isTrue);

      final again = SyncService(db);
      await again.pullAll();
      expect(again.schedulesChanged, isFalse,
          reason: 'nothing changed the second time, so nothing to re-arm');
    });
  });

  group('pull of dose logs', () {
    test('inserts a log this device has never seen', () async {
      await seedLocalSchedule(pendingSync: false);
      // Matches the local schedule so the delete-propagation check (a
      // pendingSync=false row missing from an otherwise-successful pull is
      // tombstoned — see medicineIdsMissingRemotely) doesn't remove it
      // before the dose log pull runs; a tombstoned schedule's dose logs
      // are filtered out on the way in by design.
      backend.tables['schedules'] = [remoteSchedule()];
      backend.tables['dose_logs'] = [remoteDoseLog()];

      await SyncService(db).pullAll();

      expect((await db.doseLogById('log-1'))!.action, 'taken');
    });

    test('a log already held is left exactly as it is', () async {
      await seedLocalSchedule(pendingSync: false);
      await db.recordDoseAction(
        id: 'log-1',
        scheduleId: 'sched-1',
        scheduledAt: DateTime.utc(2026, 8, 10, 8),
        action: DoseAction.snoozed,
      );
      backend.tables['dose_logs'] = [remoteDoseLog(action: 'taken')];

      await SyncService(db).pullAll();

      expect((await db.doseLogById('log-1'))!.action, 'snoozed');
    });
  });
}
