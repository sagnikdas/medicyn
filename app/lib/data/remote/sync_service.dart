import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/database.dart';

/// Pushes local-first Drift rows up to Supabase. Never the other direction
/// at reminder-fire time — the device's own alarms are always the source of
/// truth for *when* something fires; this is backup/multi-device sync only.
/// Safe to call repeatedly: unsynced rows are retried, synced ones are
/// no-ops (upsert), and a mid-sync failure just leaves `pendingSync=true`
/// for the next call to pick up.
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
        });
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
        });
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
        });
        await _db.markDoseLogSynced(log.id);
      } catch (_) {
        // Retried next call.
      }
    }
  }
}
