import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/notification_engine/schedule_validation.dart';
import '../../core/app_settings.dart';
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
    _pushedEdits = false;
    if (!AppSettings.instance.consentCloudBackup) return;
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _syncMedicines(user.id);
    await _syncSchedules(user.id);
    await _syncDoseLogs(user.id);
    await _syncDoseLogContests(user.id);
  }

  /// Best-effort `DELETE` of one medicine on the server. Postgres cascades
  /// its schedules and dose logs, which is what actually clears the family
  /// feed. Failures leave the local tombstone dirty so [syncAll] retries.
  Future<void> tryDeleteRemoteMedicine(String medicineId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    try {
      await _client
          .from('medicines')
          .delete()
          .eq('id', medicineId)
          .timeout(_networkTimeout);
      await _db.markMedicineSynced(medicineId);
      final related = await _db.schedulesForMedicine(medicineId);
      for (final s in related) {
        await _db.markScheduleSynced(s.id);
      }
      _pushedEdits = true;
    } catch (_) {
      // Retried by [syncAll].
    }
  }

  /// Brings down rows this device is missing *or* holds an older copy of —
  /// the other half of "sync". Without it, a fresh install or a second
  /// device signing into the same account starts empty, and an edit made
  /// anywhere else never arrives.
  ///
  /// Medicines and schedules resolve by last-write-wins on `updatedAt`: the
  /// remote row replaces the local one only when it is strictly newer. A
  /// local row still waiting to be pushed is treated no differently — if
  /// its own timestamp is older, it genuinely is the stale copy, and
  /// keeping it would mean an edit made on the other device silently
  /// vanishing. This is the trade last-write-wins asks for, and the reason
  /// every reminder is expected to show who last changed it.
  ///
  /// Local tombstones are the exception. Cold start pulls before it pushes,
  /// so a medicine this device has already deleted would otherwise come
  /// back from the still-live server copy, dose logs included.
  ///
  /// Dose logs stay insert-only. Nothing ever edits one, so a log this
  /// device already has can only be identical. Logs whose schedule or
  /// medicine is locally deleted are skipped rather than restored.
  /// Contest notes are the exception: they are an editable row keyed by
  /// the log, resolved by last-write-wins on `updatedAt` like medicines
  /// and schedules.
  Future<void> pullAll() async {
    if (!AppSettings.instance.consentCloudBackup) return;
    final user = _client.auth.currentUser;
    if (user == null) return;
    _schedulesChanged = false;
    _rejectedScheduleIds.clear();
    // Medicines before schedules before dose logs — each references the
    // one before it (medicine_id, schedule_id), so parents must land first.
    await _pullMedicines(user.id);
    await _pullSchedules(user.id);
    await _pullDoseLogs(user.id);
    await _pullDoseLogContests(user.id);
  }

  // Every network call below is bounded with a timeout. Without one, a
  // stalled connection (no connectivity, unreachable Supabase host, etc.)
  // leaves the `await` unresolved forever — the per-call try/catch only
  // catches *thrown* errors, not a hang — which previously froze the Save
  // button's spinner indefinitely since callers await syncAll() in the UI
  // path (see review_edit_screen.dart, home_screen.dart).
  static const _networkTimeout = Duration(seconds: 8);

  /// Set when a pull actually replaced a schedule, so the caller knows the
  /// armed alarms no longer match the database and it should reconcile.
  bool _schedulesChanged = false;
  bool get schedulesChanged => _schedulesChanged;

  /// Schedules the last pull refused to store because they could not be
  /// armed — see [_pullSchedules]. Exposed rather than logged so a caller can
  /// eventually tell the user that a reminder someone else edited did not
  /// take; nothing surfaces it yet.
  final Set<String> _rejectedScheduleIds = <String>{};
  Set<String> get rejectedScheduleIds => Set.unmodifiable(_rejectedScheduleIds);

  /// Set when [syncAll] pushed a medicine or schedule edit — i.e. a change to
  /// *what* is meant to fire, as opposed to a record of what happened. The
  /// caller uses it to decide whether the other side of a care link needs the
  /// silent re-arm push; see CareNotifier.dataChanged.
  bool _pushedEdits = false;
  bool get pushedEdits => _pushedEdits;

  /// Serialises an instant for Postgres, with its offset attached.
  ///
  /// `toIso8601String()` on a *local* `DateTime` emits no offset at all —
  /// `2026-08-19T09:00:00.000` — and Postgres reads a bare timestamp as UTC. So
  /// every client-stamped time used to land shifted by the writing device's UTC
  /// offset: a 09:00 IST dose was stored as 09:00Z and read back as 14:30 IST.
  ///
  /// Nothing on the device was ever wrong — Drift stores instants — and nothing
  /// crashed. The damage was entirely in what the *other* side was shown: a
  /// caregiver's feed, and now a missed-dose notification, quoting a time no
  /// alarm ever rang at. `toUtc()` makes the string carry its `Z`.
  @visibleForTesting
  static String isoUtc(DateTime value) => value.toUtc().toIso8601String();

  /// Missing means the row predates versioning on a server that has since
  /// been migrated — treat it as the beginning of time so any local copy
  /// with a real timestamp wins, rather than letting a null masquerade as
  /// new.
  @visibleForTesting
  static DateTime remoteUpdatedAt(Map<String, dynamic> row) {
    final raw = row['updated_at'] as String?;
    if (raw == null) return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return DateTime.parse(raw);
  }

  /// The remote copy replaces the local one when this device has never seen
  /// the row, or when the remote edit is strictly newer. Equal timestamps
  /// lose: they mean the two copies are the same version, and rewriting a
  /// row for no reason would wake every `.watch()` stream in the app.
  @visibleForTesting
  static bool remoteWins(DateTime? local, DateTime remote) {
    if (local == null) return true;
    return remote.isAfter(local);
  }

  // Each table pushes in one request rather than one per row. The previous
  // row-at-a-time loop cost a full round-trip each, and every one of them
  // could burn the 8s timeout above — so a device coming back online with a
  // backlog of 20 rows could sit in syncAll() for minutes. Postgres upserts
  // the whole batch atomically, so the all-or-nothing failure mode is also
  // simpler than a half-marked one: nothing is marked synced unless the
  // batch landed.

  Future<void> _syncMedicines(String userId) async {
    final rows = await _db.unsyncedMedicines();
    if (rows.isEmpty) return;
    final toDelete = [for (final m in rows) if (m.deleted) m];
    final toUpsert = [for (final m in rows) if (!m.deleted) m];

    if (toDelete.isNotEmpty) {
      try {
        await _client
            .from('medicines')
            .delete()
            .inFilter('id', [for (final m in toDelete) m.id])
            .timeout(_networkTimeout);
        _pushedEdits = true;
        for (final m in toDelete) {
          await _db.markMedicineSynced(m.id);
        }
      } catch (_) {
        // Leave pendingSync=true; retried on the next syncAll() call.
      }
    }

    if (toUpsert.isEmpty) return;
    try {
      await _client.from('medicines').upsert([
        for (final m in toUpsert)
          {
            'id': m.id,
            'user_id': userId,
            'drug_name': m.drugName,
            'strength': m.strength,
            'form': m.form,
            'dose_amount': m.doseAmount,
            'notes': m.notes,
            'created_at': isoUtc(m.createdAt),
            'updated_at': isoUtc(m.updatedAt),
            'updated_by': m.updatedBy,
          },
      ]).timeout(_networkTimeout);
      _pushedEdits = true;
      for (final m in toUpsert) {
        await _db.markMedicineSynced(m.id);
      }
    } catch (_) {
      // Leave pendingSync=true; retried on the next syncAll() call.
    }
  }

  Future<void> _syncSchedules(String userId) async {
    final rows = await _db.unsyncedSchedules();
    if (rows.isEmpty) return;
    final toDelete = [for (final s in rows) if (s.deleted) s];
    final toUpsert = [for (final s in rows) if (!s.deleted) s];

    if (toDelete.isNotEmpty) {
      try {
        await _client
            .from('schedules')
            .delete()
            .inFilter('id', [for (final s in toDelete) s.id])
            .timeout(_networkTimeout);
        _pushedEdits = true;
        for (final s in toDelete) {
          await _db.markScheduleSynced(s.id);
        }
      } catch (_) {
        // Retried next call.
      }
    }

    if (toUpsert.isEmpty) return;
    try {
      await _client.from('schedules').upsert([
        for (final s in toUpsert)
          {
            'id': s.id,
            'medicine_id': s.medicineId,
            'user_id': userId,
            'frequency_type': s.frequencyType,
            'times': s.times,
            'days_of_week': s.daysOfWeek,
            'interval_hours': s.intervalHours,
            'active': s.active,
            'created_at': isoUtc(s.createdAt),
            'updated_at': isoUtc(s.updatedAt),
            'updated_by': s.updatedBy,
          },
      ]).timeout(_networkTimeout);
      _pushedEdits = true;
      for (final s in toUpsert) {
        await _db.markScheduleSynced(s.id);
      }
    } catch (_) {
      // Retried next call.
    }
  }

  Future<void> _syncDoseLogs(String userId) async {
    final rows = await _db.unsyncedDoseLogs();
    if (rows.isEmpty) return;
    try {
      await _client.from('dose_logs').upsert([
        for (final log in rows)
          {
            'id': log.id,
            'schedule_id': log.scheduleId,
            'user_id': userId,
            'scheduled_at': isoUtc(log.scheduledAt),
            'action': log.action,
            'logged_at': isoUtc(log.loggedAt),
            'source': log.source,
          },
      ]).timeout(_networkTimeout);
      for (final log in rows) {
        await _db.markDoseLogSynced(log.id);
      }
    } catch (_) {
      // Retried next call.
    }
  }

  Future<void> _syncDoseLogContests(String userId) async {
    final rows = await _db.unsyncedDoseLogContests();
    if (rows.isEmpty) return;
    try {
      await _client.from('dose_log_contests').upsert([
        for (final c in rows)
          {
            'dose_log_id': c.doseLogId,
            'user_id': userId,
            'note': c.note,
            'created_at': isoUtc(c.createdAt),
            'updated_at': isoUtc(c.updatedAt),
          },
      ]).timeout(_networkTimeout);
      for (final c in rows) {
        await _db.markDoseLogContestSynced(c.doseLogId);
      }
    } catch (_) {
      // Leave pendingSync=true; retried on the next syncAll() call.
    }
  }

  Future<void> _pullMedicines(String userId) async {
    try {
      final rows = await _client.from('medicines').select().eq('user_id', userId).timeout(_networkTimeout);
      final local = await _db.medicineVersions();
      final winners = <MedicinesCompanion>[];
      for (final r in rows) {
        final id = r['id'] as String;
        final remoteStamp = remoteUpdatedAt(r);
        if (!remoteWins(local[id], remoteStamp)) continue;
        winners.add(MedicinesCompanion.insert(
          id: id,
          drugName: r['drug_name'] as String,
          strength: Value((r['strength'] as String?) ?? ''),
          form: Value((r['form'] as String?) ?? ''),
          doseAmount: Value((r['dose_amount'] as String?) ?? ''),
          notes: Value((r['notes'] as String?) ?? ''),
          createdAt: Value(DateTime.parse(r['created_at'] as String)),
          updatedAt: Value(remoteStamp),
          updatedBy: Value(r['updated_by'] as String?),
          // This copy came *from* the server, so there is nothing to push
          // back. Leaving it dirty would bounce the same row up again on
          // the next sync and re-stamp it as the newest edit.
          pendingSync: const Value(false),
        ));
      }
      await _db.applyRemoteMedicines(winners);
    } catch (_) {
      // Best-effort — retried on the next pullAll() call.
    }
  }

  Future<void> _pullSchedules(String userId) async {
    try {
      final rows = await _client.from('schedules').select().eq('user_id', userId).timeout(_networkTimeout);
      final local = await _db.scheduleVersions();
      final winners = <SchedulesCompanion>[];
      for (final r in rows) {
        final id = r['id'] as String;
        final remoteStamp = remoteUpdatedAt(r);
        if (!remoteWins(local[id], remoteStamp)) continue;

        // Nothing validates a schedule on its way into Postgres, and row-level
        // security lets a linked caregiver write this row — so these three
        // fields arrive here unchecked, from a device this one does not
        // control. A `daysOfWeek` outside 0..6 or an `intervalHours` of zero
        // is enough to leave this phone with no medication alarms at all,
        // silently, on the next reconcile.
        //
        // A row that cannot be salvaged is skipped rather than stored: the
        // local copy stays as it was, which is a working schedule, and the
        // next pull will try again if the other side corrects it. Losing an
        // edit is recoverable; losing the alarms is not.
        final fields = sanitiseScheduleFields(
          frequencyType: r['frequency_type'] as String?,
          times: (r['times'] as List?)?.whereType<String>().toList() ?? const [],
          daysOfWeek: (r['days_of_week'] as List?)?.whereType<num>().map((e) => e.toInt()).toList() ??
              const [],
          intervalHours: r['interval_hours'] as int?,
        );
        if (fields == null) {
          _rejectedScheduleIds.add(id);
          continue;
        }

        winners.add(SchedulesCompanion.insert(
          id: id,
          medicineId: r['medicine_id'] as String,
          frequencyType: fields.frequency.name,
          times: fields.times,
          daysOfWeek: Value(fields.daysOfWeek),
          intervalHours: Value(fields.intervalHours),
          active: Value(r['active'] as bool),
          createdAt: Value(DateTime.parse(r['created_at'] as String)),
          updatedAt: Value(remoteStamp),
          updatedBy: Value(r['updated_by'] as String?),
          pendingSync: const Value(false),
        ));
      }
      await _db.applyRemoteSchedules(winners);
      // A schedule that changed elsewhere is a different alarm. Nothing here
      // re-arms it — HomeScreen's reconcile does, on the next foreground.
      // Until a change can push a device awake, that is the window in which
      // the two disagree; see the release spec.
      if (winners.isNotEmpty) _schedulesChanged = true;
    } catch (_) {
      // Best-effort — retried on the next pullAll() call.
    }
  }

  Future<void> _pullDoseLogs(String userId) async {
    try {
      final rows = await _client.from('dose_logs').select().eq('user_id', userId).timeout(_networkTimeout);
      final known = await _db.doseLogIds();
      final incoming = <DoseLogsCompanion>[];
      for (final r in rows) {
        final id = r['id'] as String;
        if (known.contains(id)) continue;
        incoming.add(DoseLogsCompanion.insert(
          id: id,
          scheduleId: r['schedule_id'] as String,
          scheduledAt: DateTime.parse(r['scheduled_at'] as String),
          action: r['action'] as String,
          loggedAt: Value(DateTime.parse(r['logged_at'] as String)),
          source: Value(r['source'] as String),
          pendingSync: const Value(false),
        ));
      }
      await _db.applyRemoteDoseLogs(incoming);
    } catch (_) {
      // Best-effort — retried on the next pullAll() call.
    }
  }

  Future<void> _pullDoseLogContests(String userId) async {
    try {
      final rows = await _client
          .from('dose_log_contests')
          .select()
          .eq('user_id', userId)
          .timeout(_networkTimeout);
      final knownLogs = await _db.doseLogIds();
      final local = await _db.doseLogContestVersions();
      final winners = <DoseLogContestsCompanion>[];
      for (final r in rows) {
        final doseLogId = r['dose_log_id'] as String;
        if (!knownLogs.contains(doseLogId)) continue;
        final note = (r['note'] as String?)?.trim() ?? '';
        if (note.isEmpty) continue;
        final remoteStamp = remoteUpdatedAt(r);
        if (!remoteWins(local[doseLogId], remoteStamp)) continue;
        winners.add(DoseLogContestsCompanion.insert(
          doseLogId: doseLogId,
          note: note,
          createdAt: Value(DateTime.parse(r['created_at'] as String)),
          updatedAt: Value(remoteStamp),
          pendingSync: const Value(false),
        ));
      }
      await _db.applyRemoteDoseLogContests(winners);
    } catch (_) {
      // Best-effort — retried on the next pullAll() call.
    }
  }
}
