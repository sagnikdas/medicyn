import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart';
import 'schedule_validation.dart';

enum ReminderHealthMode { exact, inexact, notRequired, unknown }

class ReminderScheduleHealth {
  const ReminderScheduleHealth({
    required this.scheduleId,
    required this.armed,
    required this.notificationsAllowed,
    required this.exactAlarmsAllowed,
    required this.timezoneReady,
    required this.mode,
    required this.checkedAt,
    this.nextAlarmExpectedAt,
    this.errorCode,
  });

  final String scheduleId;
  final bool armed;
  final bool notificationsAllowed;
  final bool exactAlarmsAllowed;
  final bool timezoneReady;
  final ReminderHealthMode mode;
  final DateTime checkedAt;
  final DateTime? nextAlarmExpectedAt;
  final String? errorCode;

  bool get needsAttention =>
      !timezoneReady ||
      !notificationsAllowed ||
      (mode != ReminderHealthMode.notRequired && !armed) ||
      mode == ReminderHealthMode.inexact ||
      errorCode != null;

  String get shortStatus {
    if (!timezoneReady) return 'Timezone needs setup';
    if (!notificationsAllowed) return 'Notifications are off';
    if (errorCode != null || !armed) return 'Reminder needs setup';
    if (mode == ReminderHealthMode.inexact) return 'Timing may be delayed';
    if (mode == ReminderHealthMode.notRequired) return 'No alarm required';
    return 'Reminder active';
  }

  Map<String, Object?> toJson() => {
    'scheduleId': scheduleId,
    'armed': armed,
    'notificationsAllowed': notificationsAllowed,
    'exactAlarmsAllowed': exactAlarmsAllowed,
    'timezoneReady': timezoneReady,
    'mode': mode.name,
    'checkedAt': checkedAt.toUtc().toIso8601String(),
    if (nextAlarmExpectedAt != null)
      'nextAlarmExpectedAt': nextAlarmExpectedAt!.toUtc().toIso8601String(),
    if (errorCode != null) 'errorCode': errorCode,
  };

  static ReminderScheduleHealth? fromJson(Object? raw) {
    if (raw is! Map) return null;
    try {
      final map = Map<String, dynamic>.from(raw);
      final modeName = map['mode'] as String? ?? 'unknown';
      final mode = ReminderHealthMode.values.firstWhere(
        (candidate) => candidate.name == modeName,
        orElse: () => ReminderHealthMode.unknown,
      );
      return ReminderScheduleHealth(
        scheduleId: map['scheduleId'] as String,
        armed: map['armed'] as bool? ?? false,
        notificationsAllowed: map['notificationsAllowed'] as bool? ?? false,
        exactAlarmsAllowed: map['exactAlarmsAllowed'] as bool? ?? false,
        timezoneReady: map['timezoneReady'] as bool? ?? false,
        mode: mode,
        checkedAt: DateTime.parse(map['checkedAt'] as String).toLocal(),
        nextAlarmExpectedAt: map['nextAlarmExpectedAt'] == null
            ? null
            : DateTime.parse(map['nextAlarmExpectedAt'] as String).toLocal(),
        errorCode: map['errorCode'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Per-account, local-only delivery state. This is deliberately separate
/// from health data and contains no medicine names or dosage information.
class ReminderHealthStore extends ChangeNotifier {
  ReminderHealthStore._();
  static final instance = ReminderHealthStore._();

  static const _keyPrefix = 'reminder_health_v1';
  String? _ownerId;
  final Map<String, ReminderScheduleHealth> _items = {};

  List<ReminderScheduleHealth> get items =>
      _items.values.toList(growable: false);
  List<ReminderScheduleHealth> get issues =>
      items.where((item) => item.needsAttention).toList(growable: false);
  bool get hasIssues => issues.isNotEmpty;

  Future<void> loadForOwner(String ownerId) async {
    if (_ownerId == ownerId) return;
    _ownerId = ownerId;
    _items.clear();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(ownerId));
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final health = ReminderScheduleHealth.fromJson(entry.value);
            if (health != null) _items[entry.key as String] = health;
          }
        }
      } catch (_) {
        // A corrupt diagnostic snapshot must never affect reminder scheduling.
      }
    }
    notifyListeners();
  }

  Future<void> updateFromReconcile({
    required String ownerId,
    required ReconcileReport report,
    required ReminderPermissionState permissions,
    required bool timezoneReady,
  }) async {
    await loadForOwner(ownerId);
    final checkedAt = DateTime.now();
    final next = <String, ReminderScheduleHealth>{};
    for (final entry in report.results.entries) {
      final result = entry.value;
      next[entry.key] = ReminderScheduleHealth(
        scheduleId: entry.key,
        armed: result.isArmed,
        notificationsAllowed: permissions.notificationsAllowed,
        exactAlarmsAllowed: permissions.exactAlarmsAllowed,
        timezoneReady: timezoneReady,
        mode: _modeFor(result),
        checkedAt: checkedAt,
        nextAlarmExpectedAt: result.nextAlarmExpectedAt,
      );
    }
    for (final entry in report.failures.entries) {
      next[entry.key] = ReminderScheduleHealth(
        scheduleId: entry.key,
        armed: false,
        notificationsAllowed: permissions.notificationsAllowed,
        exactAlarmsAllowed: permissions.exactAlarmsAllowed,
        timezoneReady: timezoneReady,
        mode: ReminderHealthMode.unknown,
        checkedAt: checkedAt,
        errorCode: _errorCode(entry.value),
      );
    }
    _items
      ..clear()
      ..addAll(next);
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final ownerId = _ownerId;
    if (ownerId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(ownerId),
      jsonEncode({
        for (final item in _items.entries) item.key: item.value.toJson(),
      }),
    );
  }

  static ReminderHealthMode _modeFor(ScheduleArmResult result) {
    if (!result.isRequired) return ReminderHealthMode.notRequired;
    return result.mode == AndroidScheduleMode.exactAllowWhileIdle
        ? ReminderHealthMode.exact
        : ReminderHealthMode.inexact;
  }

  static String _errorCode(Object error) {
    if (error is TimezoneUnavailableException) return 'timezone_unavailable';
    if (error is UnschedulableSchedule) return 'invalid_schedule';
    return 'platform_schedule_failed';
  }

  static String _key(String ownerId) =>
      '$_keyPrefix.${Uri.encodeComponent(ownerId)}';
}
