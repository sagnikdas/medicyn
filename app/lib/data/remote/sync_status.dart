import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_settings.dart';
import '../../core/locale_dates.dart';
import '../local/database.dart';

/// Local, non-health diagnostics for cloud backup. It records only whether a
/// sync completed and how much work remains; no medicine names or dose data is
/// persisted in the status snapshot.
class SyncStatusStore extends ChangeNotifier {
  SyncStatusStore._();
  static final instance = SyncStatusStore._();

  static const _keyPrefix = 'sync_status_v1';
  String? _ownerId;
  DateTime? _lastSuccessfulAt;
  int _pendingWork = 0;
  bool _syncing = false;
  String? _errorCode;

  DateTime? get lastSuccessfulAt => _lastSuccessfulAt;
  int get pendingWork => _pendingWork;
  bool get syncing => _syncing;
  String? get errorCode => _errorCode;

  bool get backupEnabled =>
      AppSettings.instance.consentCloudBackup &&
      AppSettings.instance.consentOwnerId != AppSettings.localConsentOwnerId;

  String get summary {
    if (!backupEnabled) return 'Backup is off';
    if (_syncing) return 'Syncing…';
    if (_errorCode != null) return 'Sync needs attention';
    if (_pendingWork > 0) {
      return '$_pendingWork item${_pendingWork == 1 ? '' : 's'} waiting to sync';
    }
    if (_lastSuccessfulAt == null) return 'Backup has not run yet';
    return 'Backed up ${localeRelativeAge(_lastSuccessfulAt!)}';
  }

  Future<void> loadForOwner(String ownerId) async {
    if (_ownerId == ownerId) return;
    _ownerId = ownerId;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(ownerId));
    _lastSuccessfulAt = raw == null ? null : DateTime.tryParse(raw)?.toLocal();
    _pendingWork = 0;
    _errorCode = null;
    notifyListeners();
  }

  Future<void> markSyncing(String ownerId) async {
    await loadForOwner(ownerId);
    _syncing = true;
    _errorCode = null;
    notifyListeners();
  }

  Future<void> refresh({
    required String ownerId,
    required AppDatabase db,
    bool successful = false,
    String? errorCode,
  }) async {
    await loadForOwner(ownerId);
    _syncing = false;
    _errorCode = errorCode;
    _pendingWork = await _pendingCount(db);
    if (successful && errorCode == null) {
      _lastSuccessfulAt = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key(ownerId),
        _lastSuccessfulAt!.toUtc().toIso8601String(),
      );
    }
    notifyListeners();
  }

  static Future<int> _pendingCount(AppDatabase db) async {
    final medicines = await db.unsyncedMedicines();
    final schedules = await db.unsyncedSchedules();
    final logs = await db.unsyncedDoseLogs();
    final contests = await db.unsyncedDoseLogContests();
    final care = await db.unsyncedTodayCareReminders();
    return medicines.length +
        schedules.length +
        logs.length +
        contests.length +
        care.length;
  }

  static String _key(String ownerId) =>
      '$_keyPrefix.${Uri.encodeComponent(ownerId)}.last_success';
}
