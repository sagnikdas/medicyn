import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/notification_engine/schedule_validation.dart';
import '../../core/app_settings.dart';
import '../local/database.dart';
import 'today_care_sync_service.dart';

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
    await TodayCareSyncService(_db).sync();
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
  /// Returns whether every table pulled cleanly — see [_pullFailed]. Callers
  /// that only care about applying what came down (the historical use) can
  /// simply ignore the return value.
  Future<bool> pullAll() async {
    if (!AppSettings.instance.consentCloudBackup) return false;
    final user = _client.auth.currentUser;
    if (user == null) return false;
    _schedulesChanged = false;
    _rejectedScheduleIds.clear();
    _pullFailed = false;
    // Medicines before schedules before dose logs — each references the
    // one before it (medicine_id, schedule_id), so parents must land first.
    await _pullMedicines(user.id);
    await _pullSchedules(user.id);
    await _pullDoseLogs(user.id);
    await _pullDoseLogContests(user.id);
    // Not folded into the return value — see [_pullFailed].
    await TodayCareSyncService(_db).pull();
    return !_pullFailed;
  }

  /// The subset of [pullAll] cheap enough to run before every push, not just
  /// on a fresh install. [syncAll] has no version guard of its own — it
  /// blind-upserts every locally dirty row — so a device that has been
  /// offline can otherwise push a stale edit straight over a caregiver's
  /// newer one. Running this first gives medicines, schedules, and contest
  /// notes their last-write-wins comparison before that happens.
  ///
  /// Dose logs are left out on purpose: they are insert-only, so a push can
  /// never clobber one, and the table is the one that only grows — which is
  /// why a full [pullAll] stays reserved for first run / a new device.
  ///
  /// Returns whether every table pulled cleanly — see [pullAll].
  Future<bool> pullEditableTables() async {
    if (!AppSettings.instance.consentCloudBackup) return false;
    final user = _client.auth.currentUser;
    if (user == null) return false;
    _schedulesChanged = false;
    _rejectedScheduleIds.clear();
    _pullFailed = false;
    await _pullMedicines(user.id);
    await _pullSchedules(user.id);
    await _pullDoseLogContests(user.id);
    // Not folded into the return value — see [_pullFailed].
    await TodayCareSyncService(_db).pull();
    return !_pullFailed;
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

  /// Set when medicines, schedules, dose logs, or contest notes hit their
  /// outer try/catch below instead of completing — a network failure, not a
  /// single bad row (those are already skipped and don't count).
  /// [pullAll] and [pullEditableTables] fold this into the bool they return,
  /// which is what lets a caller tell "this pull genuinely reached the
  /// server" apart from "this pull silently gave up" — the distinction
  /// family-delivery status (#98) needs before it stamps
  /// `profiles.last_synced_at`. A pull that never runs because backup is off
  /// or nobody is signed in is not a failure either; those paths return
  /// `false` directly rather than through this flag.
  ///
  /// [TodayCareSyncService]'s own pull is deliberately not folded in here:
  /// it is a separate feed (today's care reminders), not one of the editable
  /// tables a caregiver's change-history view is about, and coupling this
  /// signal to it would make a medicine edit read as "pending" for a reason
  /// that has nothing to do with medicines or schedules.
  bool _pullFailed = false;

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
  // backlog of 20 rows could sit in syncAll() for minutes.
  //
  // A batch is atomic, though — one row Postgres rejects (an FK to a
  // medicine that itself keeps failing to push, say) fails the whole
  // request, and every *other* row batched alongside it was left pending
  // forever too. [_pushBatchOrFallback] keeps the one-request fast path but
  // retries as one-row-per-request on failure, so only the row actually at
  // fault stays stuck.
  // markSynced is also where a caller sets _pushedEdits, since only
  // medicines/schedules count as "an edit" for CareNotifier.dataChanged —
  // dose logs are a record of what happened, not a change to what fires.
  Future<void> _pushBatchOrFallback<T>({
    required List<T> rows,
    required Future<void> Function(List<T> rows) pushBatch,
    required Future<void> Function(T row) pushOne,
    required Future<void> Function(T row) markSynced,
  }) async {
    try {
      await pushBatch(rows);
      for (final row in rows) {
        await markSynced(row);
      }
      return;
    } catch (_) {
      // Falls through to one row at a time below.
    }
    for (final row in rows) {
      try {
        await pushOne(row);
        await markSynced(row);
      } catch (_) {
        // Leave pendingSync=true for this row only; retried next call.
      }
    }
  }

  Future<void> _syncMedicines(String userId) async {
    final rows = await _db.unsyncedMedicines();
    if (rows.isEmpty) return;
    final toDelete = [
      for (final m in rows)
        if (m.deleted) m,
    ];
    final toUpsert = [
      for (final m in rows)
        if (!m.deleted) m,
    ];

    if (toDelete.isNotEmpty) {
      await _pushBatchOrFallback<Medicine>(
        rows: toDelete,
        pushBatch: (ms) => _client
            .from('medicines')
            .delete()
            .inFilter('id', [for (final m in ms) m.id])
            .timeout(_networkTimeout),
        pushOne: (m) => _client
            .from('medicines')
            .delete()
            .eq('id', m.id)
            .timeout(_networkTimeout),
        markSynced: (m) async {
          _pushedEdits = true;
          await _db.markMedicineSynced(m.id);
        },
      );
    }

    if (toUpsert.isEmpty) return;
    Map<String, dynamic> row(Medicine m) => {
      'id': m.id,
      'user_id': userId,
      'drug_name': m.drugName,
      'strength': m.strength,
      'form': m.form,
      'dose_amount': m.doseAmount,
      'tablets_remaining': m.tabletsRemaining,
      'tablets_per_dose': m.tabletsPerDose,
      'notes': m.notes,
      'created_at': isoUtc(m.createdAt),
      'updated_at': isoUtc(m.updatedAt),
      'updated_by': m.updatedBy,
    };
    await _pushBatchOrFallback<Medicine>(
      rows: toUpsert,
      pushBatch: (ms) => _client
          .from('medicines')
          .upsert([for (final m in ms) row(m)])
          .timeout(_networkTimeout),
      pushOne: (m) =>
          _client.from('medicines').upsert(row(m)).timeout(_networkTimeout),
      markSynced: (m) async {
        _pushedEdits = true;
        await _db.markMedicineSynced(m.id);
      },
    );
  }

  Future<void> _syncSchedules(String userId) async {
    final rows = await _db.unsyncedSchedules();
    if (rows.isEmpty) return;
    final toDelete = [
      for (final s in rows)
        if (s.deleted) s,
    ];
    final toUpsert = [
      for (final s in rows)
        if (!s.deleted) s,
    ];

    if (toDelete.isNotEmpty) {
      await _pushBatchOrFallback<Schedule>(
        rows: toDelete,
        pushBatch: (ss) => _client
            .from('schedules')
            .delete()
            .inFilter('id', [for (final s in ss) s.id])
            .timeout(_networkTimeout),
        pushOne: (s) => _client
            .from('schedules')
            .delete()
            .eq('id', s.id)
            .timeout(_networkTimeout),
        markSynced: (s) async {
          _pushedEdits = true;
          await _db.markScheduleSynced(s.id);
        },
      );
    }

    if (toUpsert.isEmpty) return;
    Map<String, dynamic> row(Schedule s) => {
      'id': s.id,
      'medicine_id': s.medicineId,
      'user_id': userId,
      'frequency_type': s.frequencyType,
      'times': s.times,
      'days_of_week': s.daysOfWeek,
      'interval_hours': s.intervalHours,
      'status': s.status,
      'start_date': s.startDate == null ? null : isoUtc(s.startDate!),
      'end_date': s.endDate == null ? null : isoUtc(s.endDate!),
      'pause_until': s.pauseUntil == null ? null : isoUtc(s.pauseUntil!),
      'active': s.active,
      'created_at': isoUtc(s.createdAt),
      'updated_at': isoUtc(s.updatedAt),
      'timing_defined_at': isoUtc(s.timingDefinedAt),
      'updated_by': s.updatedBy,
    };
    await _pushBatchOrFallback<Schedule>(
      rows: toUpsert,
      pushBatch: (ss) => _client
          .from('schedules')
          .upsert([for (final s in ss) row(s)])
          .timeout(_networkTimeout),
      pushOne: (s) =>
          _client.from('schedules').upsert(row(s)).timeout(_networkTimeout),
      markSynced: (s) async {
        _pushedEdits = true;
        await _db.markScheduleSynced(s.id);
      },
    );
  }

  Future<void> _syncDoseLogs(String userId) async {
    final rows = await _db.unsyncedDoseLogs();
    if (rows.isEmpty) return;
    Map<String, dynamic> row(DoseLog log) => {
      'id': log.id,
      'schedule_id': log.scheduleId,
      'user_id': userId,
      'scheduled_at': isoUtc(log.scheduledAt),
      'action': log.action,
      'logged_at': isoUtc(log.loggedAt),
      'source': log.source,
    };
    await _pushBatchOrFallback<DoseLog>(
      rows: rows,
      pushBatch: (logs) => _client
          .from('dose_logs')
          .upsert([for (final log in logs) row(log)])
          .timeout(_networkTimeout),
      pushOne: (log) =>
          _client.from('dose_logs').upsert(row(log)).timeout(_networkTimeout),
      markSynced: (log) => _db.markDoseLogSynced(log.id),
    );
  }

  Future<void> _syncDoseLogContests(String userId) async {
    final rows = await _db.unsyncedDoseLogContests();
    if (rows.isEmpty) return;
    Map<String, dynamic> row(DoseLogContest c) => {
      'dose_log_id': c.doseLogId,
      'user_id': userId,
      'note': c.note,
      'created_at': isoUtc(c.createdAt),
      'updated_at': isoUtc(c.updatedAt),
    };
    await _pushBatchOrFallback<DoseLogContest>(
      rows: rows,
      pushBatch: (cs) => _client
          .from('dose_log_contests')
          .upsert([for (final c in cs) row(c)])
          .timeout(_networkTimeout),
      pushOne: (c) => _client
          .from('dose_log_contests')
          .upsert(row(c))
          .timeout(_networkTimeout),
      markSynced: (c) => _db.markDoseLogContestSynced(c.doseLogId),
    );
  }

  Future<void> _pullMedicines(String userId) async {
    try {
      final rows = await _client
          .from('medicines')
          .select()
          .eq('user_id', userId)
          .timeout(_networkTimeout);
      // Extracted before the per-row try below, since an id is always
      // present on a row Postgrest actually returned — a row missing from
      // this set genuinely no longer exists remotely, not just unparsed.
      final remoteIds = rows
          .map((r) => r['id'] as String?)
          .whereType<String>()
          .toSet();
      final local = await _db.medicineVersions();
      final winners = <MedicinesCompanion>[];
      for (final r in rows) {
        // Isolated per row: one row this device can't parse — an
        // unexpectedly null field, a date Postgres never sends malformed but
        // that a future column change could — must not cost every other row
        // already parsed out of the same response. Every field cast used to
        // sit outside a try, so the first bad one threw past the loop and
        // the catch below skipped applyRemoteMedicines entirely.
        try {
          final id = r['id'] as String;
          final remoteStamp = remoteUpdatedAt(r);
          if (!remoteWins(local[id], remoteStamp)) continue;
          winners.add(
            MedicinesCompanion.insert(
              id: id,
              drugName: r['drug_name'] as String,
              strength: Value((r['strength'] as String?) ?? ''),
              form: Value((r['form'] as String?) ?? ''),
              doseAmount: Value((r['dose_amount'] as String?) ?? ''),
              notes: Value((r['notes'] as String?) ?? ''),
              tabletsRemaining: Value(_asInt(r['tablets_remaining'])),
              tabletsPerDose: Value(_asInt(r['tablets_per_dose'])),
              createdAt: Value(DateTime.parse(r['created_at'] as String)),
              updatedAt: Value(remoteStamp),
              updatedBy: Value(r['updated_by'] as String?),
              // This copy came *from* the server, so there is nothing to push
              // back. Leaving it dirty would bounce the same row up again on
              // the next sync and re-stamp it as the newest edit.
              pendingSync: const Value(false),
            ),
          );
        } catch (_) {
          // Skip just this row; retried on the next pullAll() call.
        }
      }
      await _db.applyRemoteMedicines(winners);
      // A medicine deleted on another device is a hard DELETE there, with no
      // tombstone column to pull — its absence from this response is the
      // only signal this device gets. See medicineIdsMissingRemotely.
      final gone = await _db.medicineIdsMissingRemotely(remoteIds);
      await _db.tombstoneMedicinesMissingRemotely(gone);
    } catch (_) {
      // Best-effort — retried on the next pullAll() call.
      _pullFailed = true;
    }
  }

  Future<void> _pullSchedules(String userId) async {
    try {
      final rows = await _client
          .from('schedules')
          .select()
          .eq('user_id', userId)
          .timeout(_networkTimeout);
      final remoteIds = rows
          .map((r) => r['id'] as String?)
          .whereType<String>()
          .toSet();
      final local = await _db.scheduleVersions();
      final winners = <SchedulesCompanion>[];
      for (final r in rows) {
        // See _pullMedicines: one row's cast failing must not cost every
        // other row already parsed out of the same response.
        try {
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
            times:
                (r['times'] as List?)?.whereType<String>().toList() ?? const [],
            daysOfWeek:
                (r['days_of_week'] as List?)
                    ?.whereType<num>()
                    .map((e) => e.toInt())
                    .toList() ??
                const [],
            intervalHours: r['interval_hours'] as int?,
          );
          if (fields == null) {
            _rejectedScheduleIds.add(id);
            continue;
          }

          winners.add(
            SchedulesCompanion.insert(
              id: id,
              medicineId: r['medicine_id'] as String,
              frequencyType: fields.frequency.name,
              times: fields.times,
              daysOfWeek: Value(fields.daysOfWeek),
              intervalHours: Value(fields.intervalHours),
              status: Value(r['status'] as String?),
              startDate: Value(_asDate(r['start_date'])),
              endDate: Value(_asDate(r['end_date'])),
              pauseUntil: Value(_asDate(r['pause_until'])),
              active: Value(r['active'] as bool),
              createdAt: Value(DateTime.parse(r['created_at'] as String)),
              updatedAt: Value(remoteStamp),
              // Falls back to the row's own updatedAt for a schedule pulled
              // before the backfill migration reached the server, or from a
              // caregiver's client old enough not to send the column yet —
              // same fallback the migration itself backfilled existing rows
              // with, so this device's sweep behaves exactly as if the
              // column had always been there. See [Schedules.timingDefinedAt].
              timingDefinedAt: Value(_asDate(r['timing_defined_at']) ?? remoteStamp),
              updatedBy: Value(r['updated_by'] as String?),
              pendingSync: const Value(false),
            ),
          );
        } catch (_) {
          // Skip just this row; retried on the next pullAll() call.
        }
      }
      await _db.applyRemoteSchedules(winners);
      // A schedule deleted on another device is a hard DELETE there, with no
      // tombstone column to pull — its absence from this response is the
      // only signal this device gets. Without this, a second device kept
      // ringing forever for a medicine stopped elsewhere. See
      // scheduleIdsMissingRemotely.
      final gone = await _db.scheduleIdsMissingRemotely(remoteIds);
      await _db.tombstoneSchedulesMissingRemotely(gone);
      // A schedule that changed elsewhere is a different alarm. Nothing here
      // re-arms it — HomeScreen's reconcile does, on the next foreground.
      // Until a change can push a device awake, that is the window in which
      // the two disagree; see the release spec.
      if (winners.isNotEmpty || gone.isNotEmpty) _schedulesChanged = true;
    } catch (_) {
      // Best-effort — retried on the next pullAll() call.
      _pullFailed = true;
    }
  }

  Future<void> _pullDoseLogs(String userId) async {
    try {
      final rows = await _client
          .from('dose_logs')
          .select()
          .eq('user_id', userId)
          .timeout(_networkTimeout);
      final known = await _db.doseLogIds();
      final incoming = <DoseLogsCompanion>[];
      for (final r in rows) {
        // See _pullMedicines: one row's cast failing must not cost every
        // other row already parsed out of the same response.
        try {
          final id = r['id'] as String;
          if (known.contains(id)) continue;
          incoming.add(
            DoseLogsCompanion.insert(
              id: id,
              scheduleId: r['schedule_id'] as String,
              scheduledAt: DateTime.parse(r['scheduled_at'] as String),
              action: r['action'] as String,
              loggedAt: Value(DateTime.parse(r['logged_at'] as String)),
              source: Value(r['source'] as String),
              pendingSync: const Value(false),
            ),
          );
        } catch (_) {
          // Skip just this row; retried on the next pullAll() call.
        }
      }
      await _db.applyRemoteDoseLogs(incoming);
    } catch (_) {
      // Best-effort — retried on the next pullAll() call.
      _pullFailed = true;
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
        // See _pullMedicines: one row's cast failing must not cost every
        // other row already parsed out of the same response.
        try {
          final doseLogId = r['dose_log_id'] as String;
          if (!knownLogs.contains(doseLogId)) continue;
          final note = (r['note'] as String?)?.trim() ?? '';
          if (note.isEmpty) continue;
          final remoteStamp = remoteUpdatedAt(r);
          if (!remoteWins(local[doseLogId], remoteStamp)) continue;
          winners.add(
            DoseLogContestsCompanion.insert(
              doseLogId: doseLogId,
              note: note,
              createdAt: Value(DateTime.parse(r['created_at'] as String)),
              updatedAt: Value(remoteStamp),
              pendingSync: const Value(false),
            ),
          );
        } catch (_) {
          // Skip just this row; retried on the next pullAll() call.
        }
      }
      await _db.applyRemoteDoseLogContests(winners);
    } catch (_) {
      // Best-effort — retried on the next pullAll() call.
      _pullFailed = true;
    }
  }
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}

DateTime? _asDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}
