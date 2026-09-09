import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/consent/consent_purpose.dart';
import '../../features/consent/consent_service.dart';
import '../local/database.dart';

/// Builds the Art. 15/20 JSON copy of what Medicyn holds about this person.
///
/// Local Drift is the source of truth for medicines, schedules, dose logs
/// and contest notes. Profile, care links and care alerts are fetched from
/// Supabase when a session exists, best-effort: a failed fetch still yields
/// the local file, with the gap named in metadata.
class DataExportService {
  DataExportService(this._db, {SupabaseClient? client}) : _client = client;

  final AppDatabase _db;
  final SupabaseClient? _client;

  static const appVersion = kConsentAppVersion;

  /// Increment when the shape of an export changes. Consumers can migrate a
  /// saved export without guessing which optional fields were present.
  static const exportSchemaVersion = 6;
  static const _networkTimeout = Duration(seconds: 8);

  /// JSON-encodable map. Safe to call with no network and no account.
  Future<Map<String, dynamic>> buildExport({DateTime? now}) async {
    final exportedAt = (now ?? DateTime.now()).toUtc();
    final signedIn = _signedInUserId() != null;
    final medicines = await _db.select(_db.medicines).get();
    final schedules = await _db.select(_db.schedules).get();
    final logs = await _db.select(_db.doseLogs).get();
    final contests = await _db.select(_db.doseLogContests).get();
    final care = await _db.select(_db.todayCareReminders).get();
    final emergencyInfo = await _db.emergencyInfoOnce();

    final export = <String, dynamic>{
      'metadata': <String, dynamic>{
        'exported_at': exportedAt.toIso8601String(),
        'app_version': appVersion,
        'schema_version': exportSchemaVersion,
        'local_only': !signedIn,
      },
      'medicines': [for (final m in medicines) _medicine(m)],
      'schedules': [for (final s in schedules) _schedule(s)],
      'dose_logs': [for (final l in logs) _doseLog(l)],
      'contest_notes': [for (final c in contests) _contest(c)],
      'today_care_reminders': [
        for (final c in care)
          {
            'id': c.id,
            'title': c.title,
            'kind': c.kind,
            'scheduled_at': _iso(c.scheduledAt),
            'location': c.location,
            'notes': c.notes,
            'reminder_minutes': c.reminderMinutes,
            'completed': c.completed,
            'updated_at': _iso(c.updatedAt),
            'pending_sync': c.pendingSync,
            'deleted': c.deleted,
          },
      ],
      'emergency_info': emergencyInfo == null
          ? null
          : {
              'blood_group': emergencyInfo.bloodGroup,
              'allergies': emergencyInfo.allergies,
              'allergies_severe': emergencyInfo.allergiesSevere,
              'conditions': emergencyInfo.conditions,
              'notes': emergencyInfo.notes,
              'insurance_number': emergencyInfo.insuranceNumber,
              'national_id': emergencyInfo.nationalId,
              'health_card_number': emergencyInfo.healthCardNumber,
              'emergency_contact_name': emergencyInfo.emergencyContactName,
              'emergency_contact_phone': emergencyInfo.emergencyContactPhone,
              'updated_at': _iso(emergencyInfo.updatedAt),
            },
      'consents': {
        for (final purpose in ConsentPurpose.values)
          purpose.id: ConsentService.instance.isGranted(purpose),
      },
    };

    if (signedIn) {
      await _addRemote(export);
    }
    return export;
  }

  Future<String> encodeExport({DateTime? now}) async {
    final data = await buildExport(now: now);
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// Writes the JSON under the app temp dir and opens the system share sheet.
  Future<void> exportAndShare({
    DateTime? now,
    Rect? sharePositionOrigin,
  }) async {
    final json = await encodeExport(now: now);
    final dir = await getTemporaryDirectory();
    final stamp = (now ?? DateTime.now())
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('.', '');
    final file = File(p.join(dir.path, 'medicyn-data-$stamp.json'));
    await file.writeAsString(json);
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          subject: 'My Medicyn data',
          sharePositionOrigin: sharePositionOrigin,
        ),
      );
    } finally {
      // The share sheet has received its copy; do not leave a plaintext
      // export containing health history in the app cache.
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Best-effort cleanup. The export itself was already delivered.
      }
    }
  }

  Future<void> _addRemote(Map<String, dynamic> export) async {
    final client = _tryClient();
    final userId = _signedInUserId();
    if (client == null || userId == null) return;

    final gaps = <String>[];
    final metadata = export['metadata'] as Map<String, dynamic>;

    try {
      final rows = await client
          .from('profiles')
          .select(
            'display_name, timezone, last_seen_at, notifications_allowed, '
            'exact_alarms_allowed, battery_exemption, armed_alarm_count, health_checked_at',
          )
          .eq('user_id', userId)
          .limit(1)
          .timeout(_networkTimeout);
      export['profile'] = rows.isEmpty
          ? null
          : Map<String, dynamic>.from(rows.first);
    } catch (_) {
      gaps.add('profile');
    }

    try {
      final rows = await client
          .from('care_links')
          .select()
          .timeout(_networkTimeout);
      export['care_links'] = [
        for (final r in rows) Map<String, dynamic>.from(r),
      ];
    } catch (_) {
      gaps.add('care_links');
    }

    try {
      final rows = await client
          .from('care_alerts')
          .select()
          .timeout(_networkTimeout);
      export['care_alerts'] = [
        for (final r in rows) Map<String, dynamic>.from(r),
      ];
    } catch (_) {
      gaps.add('care_alerts');
    }

    try {
      final rows = await client
          .from('medicine_edits')
          .select()
          .eq('owner_id', userId)
          .timeout(_networkTimeout);
      export['medicine_edits'] = [
        for (final r in rows) Map<String, dynamic>.from(r),
      ];
    } catch (_) {
      gaps.add('medicine_edits');
    }

    if (gaps.isNotEmpty) metadata['remote_gaps'] = gaps;
  }

  String? _signedInUserId() {
    try {
      return (_client ?? Supabase.instance.client).auth.currentUser?.id;
    } on AssertionError {
      return null;
    } catch (_) {
      return null;
    }
  }

  SupabaseClient? _tryClient() {
    if (_client != null) return _client;
    try {
      return Supabase.instance.client;
    } on AssertionError {
      return null;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _medicine(Medicine m) => {
    'id': m.id,
    'drug_name': m.drugName,
    'strength': m.strength,
    'form': m.form,
    'dose_amount': m.doseAmount,
    'tablets_remaining': m.tabletsRemaining,
    'tablets_per_dose': m.tabletsPerDose,
    'notes': m.notes,
    'created_at': _iso(m.createdAt),
    'updated_at': _iso(m.updatedAt),
    'updated_by': m.updatedBy,
    'deleted': m.deleted,
    'pending_sync': m.pendingSync,
  };

  Map<String, dynamic> _schedule(Schedule s) => {
    'id': s.id,
    'medicine_id': s.medicineId,
    'frequency_type': s.frequencyType,
    'times': s.times,
    'days_of_week': s.daysOfWeek,
    'interval_hours': s.intervalHours,
    'status': s.status,
    'start_date': s.startDate?.toIso8601String(),
    'end_date': s.endDate?.toIso8601String(),
    'pause_until': s.pauseUntil?.toIso8601String(),
    'active': s.active,
    'created_at': _iso(s.createdAt),
    'updated_at': _iso(s.updatedAt),
    'updated_by': s.updatedBy,
    'deleted': s.deleted,
    'pending_sync': s.pendingSync,
  };

  Map<String, dynamic> _doseLog(DoseLog l) => {
    'id': l.id,
    'schedule_id': l.scheduleId,
    'scheduled_at': _iso(l.scheduledAt),
    'action': l.action,
    'logged_at': _iso(l.loggedAt),
    'source': l.source,
    'pending_sync': l.pendingSync,
  };

  Map<String, dynamic> _contest(DoseLogContest c) => {
    'dose_log_id': c.doseLogId,
    'note': c.note,
    'created_at': _iso(c.createdAt),
    'updated_at': _iso(c.updatedAt),
    'pending_sync': c.pendingSync,
  };

  static String _iso(DateTime value) => value.toUtc().toIso8601String();
}

/// Visible so a test can assert we never put secrets in the file. The
/// export builder does not read these stores; this list is the documentation.
@visibleForTesting
const exportExcludedSecrets = ['fcm_token', 'encryption_key', 'refresh_token'];
