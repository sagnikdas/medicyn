import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/database.dart';
import '../local/tables.dart';

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
    _pushedEdits = false;
    _pushedMissedDoseIds = const [];
    await _syncMedicines(user.id);
    await _syncSchedules(user.id);
    await _syncDoseLogs(user.id);
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
  /// Dose logs stay insert-only. Nothing ever edits one, so a log this
  /// device already has can only be identical.
  Future<void> pullAll() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    _schedulesChanged = false;
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

  /// Set when a pull actually replaced a schedule, so the caller knows the
  /// armed alarms no longer match the database and it should reconcile.
  bool _schedulesChanged = false;
  bool get schedulesChanged => _schedulesChanged;

  /// Set when [syncAll] pushed a medicine or schedule edit — i.e. a change to
  /// *what* is meant to fire, as opposed to a record of what happened. The
  /// caller uses it to decide whether the other side of a care link needs the
  /// silent re-arm push; see CareNotifier.dataChanged.
  bool _pushedEdits = false;
  bool get pushedEdits => _pushedEdits;

  /// Ids of the missed-dose logs [syncAll] just pushed. These, and only these,
  /// are what the caregiver's alert is raised about.
  ///
  /// Reported rather than announced from inside this class on purpose: sync is
  /// documented as never being in the reminder-firing path, and giving it a
  /// second responsibility — deciding who to tell — would make that harder to
  /// keep true.
  List<String> _pushedMissedDoseIds = const [];
  List<String> get pushedMissedDoseIds => _pushedMissedDoseIds;

  /// The ids in [logs] that a caregiver should hear about: the missed ones, and
  /// nothing else.
  ///
  /// Its own function because the mistake it prevents is not a crash. A `taken`
  /// or `snoozed` log slipping through would ring someone's phone in another
  /// city to tell them their mother *did* take her tablet, at whatever hour she
  /// took it — the fastest way to teach a family to mute the app that is
  /// supposed to be watching.
  @visibleForTesting
  static List<String> missedDoseIdsIn(List<DoseLog> logs) => [
        for (final log in logs)
          if (log.action == DoseAction.missed.name) log.id,
      ];

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
    try {
      await _client.from('medicines').upsert([
        for (final m in rows)
          {
            'id': m.id,
            'user_id': userId,
            'drug_name': m.drugName,
            'strength': m.strength,
            'form': m.form,
            'dose_amount': m.doseAmount,
            'notes': m.notes,
            'created_at': m.createdAt.toIso8601String(),
            'updated_at': m.updatedAt.toIso8601String(),
            'updated_by': m.updatedBy,
          },
      ]).timeout(_networkTimeout);
      _pushedEdits = true;
      for (final m in rows) {
        await _db.markMedicineSynced(m.id);
      }
    } catch (_) {
      // Leave pendingSync=true; retried on the next syncAll() call.
    }
  }

  Future<void> _syncSchedules(String userId) async {
    final rows = await _db.unsyncedSchedules();
    if (rows.isEmpty) return;
    try {
      await _client.from('schedules').upsert([
        for (final s in rows)
          {
            'id': s.id,
            'medicine_id': s.medicineId,
            'user_id': userId,
            'frequency_type': s.frequencyType,
            'times': s.times,
            'days_of_week': s.daysOfWeek,
            'interval_hours': s.intervalHours,
            'active': s.active,
            'created_at': s.createdAt.toIso8601String(),
            'updated_at': s.updatedAt.toIso8601String(),
            'updated_by': s.updatedBy,
          },
      ]).timeout(_networkTimeout);
      _pushedEdits = true;
      for (final s in rows) {
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
            'scheduled_at': log.scheduledAt.toIso8601String(),
            'action': log.action,
            'logged_at': log.loggedAt.toIso8601String(),
            'source': log.source,
          },
      ]).timeout(_networkTimeout);
      // Only what landed on this call. A dose already marked synced was
      // announced (or de-duplicated away) on whichever earlier call pushed it,
      // so re-listing it here would be the app asking to be told to shut up.
      _pushedMissedDoseIds = missedDoseIdsIn(rows);
      for (final log in rows) {
        await _db.markDoseLogSynced(log.id);
      }
    } catch (_) {
      // Retried next call.
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
        winners.add(SchedulesCompanion.insert(
          id: id,
          medicineId: r['medicine_id'] as String,
          frequencyType: r['frequency_type'] as String,
          times: (r['times'] as List).map((e) => e as String).toList(),
          daysOfWeek: Value((r['days_of_week'] as List).map((e) => e as int).toList()),
          intervalHours: Value(r['interval_hours'] as int?),
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
}
