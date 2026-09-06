import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medicyn/core/app_settings.dart';
import 'package:medicyn/data/local/database.dart';
import 'package:medicyn/data/remote/sync_service.dart';
import 'package:medicyn/data/remote/sync_status.dart';
import 'package:medicyn/data/remote/today_care_sync_service.dart';
import 'package:medicyn/features/reminders_home/today_care_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_supabase.dart';

const _owner = '11111111-1111-1111-1111-111111111111';
const _table = TodayCareSyncService.table;

/// Stateful PostgREST transport for two independent device databases. The
/// actual server guard and RLS are separately exercised by the SQL tests.
class _CareBackend extends FakePostgrest {
  final rows = <String, Map<String, dynamic>>{};
  Future<void> Function()? beforeWriteReply;
  bool failReads = false;

  @override
  http.Client get client => MockClient((request) async {
    requests.add(RecordedRequest(request.method, request.url, request.body));
    final care = request.url.pathSegments.last == _table;
    http.Response reply(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      request: request,
      headers: {'content-type': 'application/json'},
    );
    if (!care) return reply([]);
    if (failing.contains(_table) || (failReads && request.method == 'GET')) {
      return reply({'message': 'Offline', 'code': '500'}, 500);
    }
    if (request.method == 'GET') {
      final owner = request.url.queryParameters['user_id']?.substring(3);
      final ordered = rows.values.where((r) => r['user_id'] == owner).toList()
        ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
      final start = int.parse(request.url.queryParameters['offset'] ?? '0');
      final limit = int.parse(request.url.queryParameters['limit'] ?? '500');
      return reply(ordered.skip(start).take(limit).toList());
    }
    final incoming = jsonDecode(request.body) as Map<String, dynamic>;
    final id = incoming['id'] as String;
    final old = rows[id];
    if (old == null ||
        DateTime.parse(
          incoming['updated_at'] as String,
        ).isAfter(DateTime.parse(old['updated_at'] as String))) {
      rows[id] = incoming;
    }
    final returned = Map<String, dynamic>.from(rows[id]!);
    final callback = beforeWriteReply;
    beforeWriteReply = null;
    await callback?.call();
    return reply(returned);
  });
}

TodayCareReminder _care(String id, {String kind = 'test'}) => TodayCareReminder(
  id: id,
  title: 'Blood test',
  kind: kind,
  scheduledAt: DateTime(2026, 9, 10, 10),
  location: 'Clinic',
  notes: 'Bring referral',
  reminderMinutes: 30,
  completed: false,
  updatedAt: DateTime.utc(2026, 9, 1),
  pendingSync: true,
  deleted: false,
);

Map<String, dynamic> _remote(String id, {String owner = _owner}) => {
  'id': id,
  'user_id': owner,
  'title': 'Remote appointment',
  'kind': 'appointment',
  'scheduled_at': '2026-09-10T10:00:00Z',
  'location': 'Clinic',
  'notes': 'Referral',
  'reminder_minutes': 30,
  'completed': false,
  'updated_at': '2026-09-01T00:00:00Z',
  'deleted': false,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backend = _CareBackend();
  late AppDatabase first;
  late AppDatabase second;

  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    SharedPreferences.setMockInitialValues({});
    await initFakeSupabase(backend: backend, userId: _owner);
  });
  tearDownAll(() async {
    await Supabase.instance.dispose();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AppSettings.instance.resetForTest();
    await AppSettings.instance.init(consentOwnerId: _owner);
    await AppSettings.instance.setConsentCloudBackup(true);
    backend.rows.clear();
    backend.requests.clear();
    backend.failing.clear();
    backend.failReads = false;
    backend.beforeWriteReply = null;
    first = AppDatabase.forTesting(NativeDatabase.memory());
    second = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() async {
    await first.close();
    await second.close();
  });

  test(
    'all five categories reach Supabase and restore on a fresh device',
    () async {
      for (final kind in TodayCareKind.values) {
        await TodayCareStore(first).save(_care(kind.name, kind: kind.name));
      }
      await SyncService(first).syncAll();
      expect(backend.rows, hasLength(5));
      for (final row in backend.rows.values) {
        expect(row['user_id'], _owner);
        expect(row['scheduled_at'], endsWith('Z'));
        expect(row['updated_at'], endsWith('Z'));
        expect(row['location'], 'Clinic');
        expect(row['notes'], 'Bring referral');
        expect(row['reminder_minutes'], 30);
      }
      expect(await first.unsyncedTodayCareReminders(), isEmpty);
      await SyncService(second).pullAll();
      expect(
        (await TodayCareStore(second).watch().first).map((r) => r.kind),
        unorderedEquals(TodayCareKind.values.map((k) => k.name)),
      );
    },
  );

  test(
    'edits, completion, deletion and undo propagate between devices',
    () async {
      final store = TodayCareStore(first);
      final original = _care('care-1');
      await store.save(original);
      await TodayCareSyncService(first).sync();
      await TodayCareSyncService(second).pull();
      await store.save(
        original.copyWith(
          title: 'New title',
          completed: true,
          reminderMinutes: const Value(null),
        ),
      );
      await TodayCareSyncService(first).sync();
      await SyncService(second).pullEditableTables();
      final changed = (await TodayCareStore(second).watch().first).single;
      expect(changed.title, 'New title');
      expect(changed.completed, isTrue);
      expect(changed.reminderMinutes, isNull);
      await store.remove(original.id);
      await TodayCareSyncService(first).sync();
      await TodayCareSyncService(second).pull();
      expect(await TodayCareStore(second).watch().first, isEmpty);
      expect(backend.rows[original.id]!['deleted'], isTrue);
      await store.save(original);
      await TodayCareSyncService(first).sync();
      await TodayCareSyncService(second).pull();
      final restored = (await TodayCareStore(second).watch().first).single;
      expect(restored.title, original.title);
      expect(restored.completed, isFalse);
    },
  );

  test(
    'offline changes and deletions stay queued and retry successfully',
    () async {
      final store = TodayCareStore(first);
      await store.save(_care('care-1'));
      backend.failing.add(_table);
      expect(await TodayCareSyncService(first).sync(), isFalse);
      expect(await first.unsyncedTodayCareReminders(), hasLength(1));
      await SyncStatusStore.instance.refresh(ownerId: _owner, db: first);
      expect(SyncStatusStore.instance.pendingWork, 1);
      backend.failing.clear();
      expect(await TodayCareSyncService(first).sync(), isTrue);
      await store.remove('care-1');
      backend.failing.add(_table);
      expect(await TodayCareSyncService(first).sync(), isFalse);
      expect((await first.unsyncedTodayCareReminders()).single.deleted, isTrue);
      backend.failing.clear();
      expect(await TodayCareSyncService(first).sync(), isTrue);
      expect(backend.rows['care-1']!['deleted'], isTrue);
      expect(await first.unsyncedTodayCareReminders(), isEmpty);
    },
  );

  test(
    'an edit during upload stays pending until its own version is saved',
    () async {
      final store = TodayCareStore(first);
      final original = _care('care-1');
      await store.save(original);
      backend.beforeWriteReply = () =>
          store.save(original.copyWith(title: 'Edited during upload'));
      await TodayCareSyncService(first).sync();
      final pending = (await first.unsyncedTodayCareReminders()).single;
      expect(pending.title, 'Edited during upload');
      expect(backend.rows['care-1']!['title'], original.title);
      await TodayCareSyncService(first).sync();
      expect(backend.rows['care-1']!['title'], pending.title);
      expect(await first.unsyncedTodayCareReminders(), isEmpty);
    },
  );

  test(
    'server rejection of a stale upsert restores the newer deletion',
    () async {
      await TodayCareStore(first).save(_care('care-1'));
      backend.rows['care-1'] = _remote('care-1')
        ..['updated_at'] = DateTime.now()
            .toUtc()
            .add(const Duration(hours: 1))
            .toIso8601String()
        ..['deleted'] = true;
      backend.failReads = true;
      await TodayCareSyncService(first).sync();
      expect(await TodayCareStore(first).watch().first, isEmpty);
      expect(await first.unsyncedTodayCareReminders(), isEmpty);
      expect(backend.rows['care-1']!['deleted'], isTrue);
    },
  );

  test('pull paginates and requests only the signed-in owner', () async {
    for (var i = 0; i < 501; i++) {
      final id = i.toString().padLeft(4, '0');
      backend.rows[id] = _remote(id);
    }
    backend.rows['stranger'] = _remote('stranger', owner: 'another-account');
    expect(await TodayCareSyncService(first).pull(), isTrue);
    expect(await TodayCareStore(first).watch().first, hasLength(501));
    expect(backend.requests, hasLength(2));
    for (final request in backend.requests) {
      expect(request.url.queryParameters['user_id'], 'eq.$_owner');
    }
  });

  test('backup disabled and account mismatch never send data', () async {
    await TodayCareStore(first).save(_care('care-1'));
    await AppSettings.instance.setConsentCloudBackup(false);
    expect(await TodayCareSyncService(first).sync(), isFalse);
    expect(backend.requests, isEmpty);
    await AppSettings.instance.activateConsentOwner('another-account');
    await AppSettings.instance.setConsentCloudBackup(true);
    expect(await TodayCareSyncService(first).sync(), isFalse);
    expect(backend.requests, isEmpty);
    expect(await first.unsyncedTodayCareReminders(), hasLength(1));
  });
}
