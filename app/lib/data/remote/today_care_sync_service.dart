import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_settings.dart';
import '../local/database.dart';

/// Each account has its own encrypted database. Supabase RLS separately
/// enforces ownership of every remote row. Tombstones travel with the records
/// so an offline device learns about deletions without inferring them from
/// an incomplete or paginated response.
///
/// Pulls are incremental: rather than fetching every row on every call, [_pull]
/// asks only for rows whose `sync_seq` is past this device's last-seen cursor.
/// `sync_seq` is a server-assigned counter, deliberately not the
/// client-supplied `updated_at` used for conflict resolution — see the
/// migration that adds it for why reusing `updated_at` as a cursor would be
/// unsafe.
///
/// The cursor is kept in memory only, keyed by [db] like [_inFlight] below
/// (never in a process-wide singleton such as `AppSettings`): two accounts
/// signed in to the same app process — or, in tests, two [AppDatabase]
/// instances standing in for two physical devices — must never share one
/// cursor, since each has pulled a different, independent set of rows. The
/// cost is a full pull again after every cold start; unlike a poll repeated
/// every 30s while the app sits open, that one-time cost is negligible.
class TodayCareSyncService {
  TodayCareSyncService(this.db);
  final AppDatabase db;

  static const table = 'today_care_reminders';
  static const _timeout = Duration(seconds: 8);
  static const _pageSize = 500;
  static final _inFlight = Expando<Future<bool>>();
  static final _cursors = Expando<int>();
  SupabaseClient get _client => Supabase.instance.client;

  Future<bool> pull() => _serialise(push: false);
  Future<bool> sync() => _serialise(push: true);

  @visibleForTesting
  static int cursorFor(AppDatabase db) => _cursors[db] ?? 0;

  Future<bool> _serialise({required bool push}) async {
    if (!AppSettings.instance.consentCloudBackup) return false;
    final userId = _client.auth.currentUser?.id;
    if (userId == null || !_sameAccount(userId)) return false;
    final previous = _inFlight[db];
    final next = () async {
      if (previous != null) await previous;
      if (!_sameAccount(userId)) return false;
      // Even if a pull fails, the server's version guard makes pushing safe.
      final pulled = await _pull(userId);
      final pushed = push ? await _push(userId) : true;
      return pulled && pushed;
    }();
    _inFlight[db] = next;
    try {
      return await next;
    } finally {
      if (identical(_inFlight[db], next)) _inFlight[db] = null;
    }
  }

  bool _sameAccount(String userId) =>
      AppSettings.instance.consentCloudBackup &&
      AppSettings.instance.consentOwnerId == userId &&
      _client.auth.currentUser?.id == userId;

  Future<bool> _pull(String userId) async {
    // Fixed for the whole call: a cursor that moved mid-pagination could
    // make a later page skip a row a concurrent write placed between pages.
    final cursor = _cursors[db] ?? 0;
    var maxSeen = cursor;
    try {
      for (var start = 0; ; start += _pageSize) {
        if (!_sameAccount(userId)) return false;
        final rows = await _client
            .from(table)
            .select()
            .eq('user_id', userId)
            .gt('sync_seq', cursor)
            .order('sync_seq')
            .range(start, start + _pageSize - 1)
            .timeout(_timeout);
        if (!_sameAccount(userId)) return false;
        for (final row in rows) {
          await db.applyRemoteTodayCareReminder(_decode(row, userId));
          maxSeen = _laterSeq(maxSeen, row);
        }
        if (rows.length < _pageSize) break;
      }
    } catch (_) {
      return false;
    }
    if (maxSeen > cursor) _cursors[db] = maxSeen;
    return true;
  }

  static int _laterSeq(int current, Map<String, dynamic> row) {
    final seq = row['sync_seq'];
    if (seq is! num || seq <= current) return current;
    return seq.toInt();
  }

  Future<bool> _push(String userId) async {
    var successful = true;
    final pending = await db.unsyncedTodayCareReminders();
    for (final reminder in pending) {
      if (!_sameAccount(userId)) return false;
      try {
        // RETURNING is essential: a newer server edit may have won while
        // this phone was offline. Only acknowledge the version returned.
        final row = await _client
            .from(table)
            .upsert(_encode(reminder, userId))
            .select()
            .single()
            .timeout(_timeout);
        if (!_sameAccount(userId)) return false;
        await db.applyRemoteTodayCareReminder(_decode(row, userId));
        // This device already has the content of its own just-accepted
        // write, so there is no need to fetch it again on the next pull.
        _cursors[db] = _laterSeq(_cursors[db] ?? 0, row);
      } catch (_) {
        successful = false;
        // The durable pending row includes deletions; the next pass retries.
      }
    }
    return successful;
  }

  static Map<String, dynamic> _encode(TodayCareReminder row, String userId) => {
    'id': row.id,
    'user_id': userId,
    'title': row.title,
    'kind': row.kind,
    'scheduled_at': row.scheduledAt.toUtc().toIso8601String(),
    'location': row.location,
    'notes': row.notes,
    'reminder_minutes': row.reminderMinutes,
    'completed': row.completed,
    'updated_at': row.updatedAt.toUtc().toIso8601String(),
    'deleted': row.deleted,
  };

  static TodayCareReminder _decode(Map<String, dynamic> row, String userId) {
    if (row['user_id'] != userId) throw const FormatException('Wrong owner');
    return TodayCareReminder(
      id: row['id'] as String,
      title: row['title'] as String,
      kind: row['kind'] as String,
      scheduledAt: DateTime.parse(row['scheduled_at'] as String),
      location: row['location'] as String,
      notes: row['notes'] as String,
      reminderMinutes: row['reminder_minutes'] as int?,
      completed: row['completed'] as bool,
      updatedAt: DateTime.parse(row['updated_at'] as String),
      pendingSync: false,
      deleted: row['deleted'] as bool,
    );
  }
}
