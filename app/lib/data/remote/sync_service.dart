import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/database.dart';

/// Syncs local-first Drift rows with Supabase. Never in the reminder-firing
/// path — the device's own alarms are always the source of truth for *when*
/// something fires; this is backup/multi-device sync only. Safe to call
/// repeatedly: [syncAll] retries unsynced rows and no-ops on synced ones,
/// [pullAll] inserts only rows this device doesn't have yet, and a mid-sync
/// failure just leaves things for the next call to pick up.
class SyncService {
  SyncService(this._db);
  final AppDatabase _db;

  SupabaseClient get _client => Supabase.instance.client;

  Future<void> syncAll() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _syncMedicines(user.id);
    await _syncSchedules(user.id);
    await _syncDoseLogs(user.id);
  }

  /// Restores rows that exist on Supabase but not on this device — the
  /// other half of "sync": without this, a fresh install or a second device
  /// signing into the same account starts with an empty list even though
  /// the account already has reminders backed up.
  ///
  /// Insert-only (never overwrites a locally-existing row), so this does
  /// *not* propagate an edit made to an existing reminder on another device
  /// to a device that already has a local copy of that row — the schema has
  /// no `updated_at` to resolve that conflict safely. What it does fix: a
  /// device that doesn't yet have a given row (new install, new device, or
  /// a row created elsewhere) will end up with it.
  Future<void> pullAll() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    // Medicines before schedules before dose logs — each references the
    // one before it (medicine_id, schedule_id), so parents must land first.
    await _pullMedicines(user.id);
    await _pullSchedules(user.id);
    await _pullDoseLogs(user.id);
  }

  // Every network call below is bounded with a timeout. Without one, a
  // stalled connection (no connectivity, unreachable Supabase host, etc.)
  // leaves the `await` unresolved forever — the per-call try/catch only
  // catches *thrown* errors, not a hang — which previously froze the Save
  // button's spinner indefinitely since callers await syncAll() in the UI
  // path (see review_edit_screen.dart, home_screen.dart).
  static const _networkTimeout = Duration(seconds: 8);

  Future<void> _syncMedicines(String userId) async {
    for (final m in await _db.unsyncedMedicines()) {
      try {
        await _client.from('medicines').upsert({
          'id': m.id,
          'user_id': userId,
          'drug_name': m.drugName,
          'strength': m.strength,
          'form': m.form,
          'dose_amount': m.doseAmount,
          'notes': m.notes,
          'created_at': m.createdAt.toIso8601String(),
        }).timeout(_networkTimeout);
        await _db.markMedicineSynced(m.id);
      } catch (_) {
        // Leave pendingSync=true; retried on the next syncAll() call.
      }
    }
  }

  Future<void> _syncSchedules(String userId) async {
    for (final s in await _db.unsyncedSchedules()) {
      try {
        await _client.from('schedules').upsert({
          'id': s.id,
          'medicine_id': s.medicineId,
          'user_id': userId,
          'frequency_type': s.frequencyType,
          'times': s.times,
          'days_of_week': s.daysOfWeek,
          'interval_hours': s.intervalHours,
          'active': s.active,
          'created_at': s.createdAt.toIso8601String(),
        }).timeout(_networkTimeout);
        await _db.markScheduleSynced(s.id);
      } catch (_) {
        // Retried next call.
      }
    }
  }

  Future<void> _syncDoseLogs(String userId) async {
    for (final log in await _db.unsyncedDoseLogs()) {
      try {
        await _client.from('dose_logs').upsert({
          'id': log.id,
          'schedule_id': log.scheduleId,
          'user_id': userId,
          'scheduled_at': log.scheduledAt.toIso8601String(),
          'action': log.action,
          'logged_at': log.loggedAt.toIso8601String(),
          'source': log.source,
        }).timeout(_networkTimeout);
        await _db.markDoseLogSynced(log.id);
      } catch (_) {
        // Retried next call.
      }
    }
  }

  Future<void> _pullMedicines(String userId) async {
    try {
      final rows = await _client.from('medicines').select().eq('user_id', userId).timeout(_networkTimeout);
      for (final r in rows) {
        await _db.insertMedicineIfAbsent(MedicinesCompanion.insert(
          id: r['id'] as String,
          drugName: r['drug_name'] as String,
          strength: Value((r['strength'] as String?) ?? ''),
          form: Value((r['form'] as String?) ?? ''),
          doseAmount: Value((r['dose_amount'] as String?) ?? ''),
          notes: Value((r['notes'] as String?) ?? ''),
          createdAt: Value(DateTime.parse(r['created_at'] as String)),
          pendingSync: const Value(false),
        ));
      }
    } catch (_) {
      // Best-effort — retried on the next pullAll() call.
    }
  }

  Future<void> _pullSchedules(String userId) async {
    try {
      final rows = await _client.from('schedules').select().eq('user_id', userId).timeout(_networkTimeout);
      for (final r in rows) {
        await _db.insertScheduleIfAbsent(SchedulesCompanion.insert(
          id: r['id'] as String,
          medicineId: r['medicine_id'] as String,
          frequencyType: r['frequency_type'] as String,
          times: (r['times'] as List).map((e) => e as String).toList(),
          daysOfWeek: Value((r['days_of_week'] as List).map((e) => e as int).toList()),
          intervalHours: Value(r['interval_hours'] as int?),
          active: Value(r['active'] as bool),
          createdAt: Value(DateTime.parse(r['created_at'] as String)),
          pendingSync: const Value(false),
        ));
      }
    } catch (_) {
      // Best-effort — retried on the next pullAll() call.
    }
  }

  Future<void> _pullDoseLogs(String userId) async {
    try {
      final rows = await _client.from('dose_logs').select().eq('user_id', userId).timeout(_networkTimeout);
      for (final r in rows) {
        await _db.insertDoseLogIfAbsent(DoseLogsCompanion.insert(
          id: r['id'] as String,
          scheduleId: r['schedule_id'] as String,
          scheduledAt: DateTime.parse(r['scheduled_at'] as String),
          action: r['action'] as String,
          loggedAt: Value(DateTime.parse(r['logged_at'] as String)),
          source: Value(r['source'] as String),
          pendingSync: const Value(false),
        ));
      }
    } catch (_) {
      // Best-effort — retried on the next pullAll() call.
    }
  }
}
