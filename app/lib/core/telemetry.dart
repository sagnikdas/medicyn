import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Non-health product events used to measure the activation and reliability
/// funnel. Values intentionally describe only buckets and outcomes; callers
/// must never pass medicine names, free text, identifiers, or exact health
/// timestamps.
enum MedicynEvent {
  onboardingViewed,
  onboardingCompleted,
  addStarted,
  addCompleted,
  permissionPrompted,
  permissionResult,
  reminderArmAttempt,
  reminderArmResult,
  doseResponse,
  syncAttempt,
  syncResult,
  careInviteCreated,
  careInviteClaimed,
  careInviteConfirmed,
  alertAttempt,
  alertAcknowledged,
  reportExported,
  paywallViewed,
  trialStarted,
  purchaseState,
}

class MedicynTelemetry {
  MedicynTelemetry._();
  static final instance = MedicynTelemetry._();

  bool _available = false;

  /// Brings up Firebase (if [PushService] hasn't already) and wires
  /// Crashlytics into Flutter's and the platform's uncaught-error hooks.
  /// Call once, before `runApp` — as early as possible, so a crash during
  /// the app's own startup work is still captured.
  ///
  /// Degrades to a no-op the same way [PushService] does: when there is no
  /// `google-services.json` / `GoogleService-Info.plist` in this build (a
  /// fresh checkout, both git-ignored), `Firebase.initializeApp()` throws,
  /// [_available] stays false, and every method below is a silent no-op —
  /// the app behaves exactly as it would without Crashlytics at all.
  Future<void> init() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _available = true;
    } catch (_) {
      _available = false;
      return;
    }
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  /// Records a breadcrumb-style log line ahead of whatever crash (if any)
  /// follows it. Only allow-listed keys/values are included — see
  /// [_allowedKeys] and [_isSafeValue] — so a caller cannot accidentally log
  /// a medicine name, free text, or an identifier into Crashlytics.
  Future<void> record(
    MedicynEvent event, {
    Map<String, Object?> properties = const {},
  }) async {
    if (!_available) return;
    final safe = <String, Object?>{};
    for (final entry in properties.entries) {
      if (_allowedKeys.contains(entry.key) && _isSafeValue(entry.value)) {
        safe[entry.key] = entry.value;
      }
    }
    final fields = safe.entries.map((e) => '${e.key}=${e.value}').join(' ');
    await FirebaseCrashlytics.instance.log(
      fields.isEmpty ? event.name : '${event.name} $fields',
    );
  }

  /// Reports one of a small, named set of handled-but-notable failures as a
  /// non-fatal Crashlytics error. Anything not in [_allowedErrorCodes] is
  /// dropped rather than reported, on purpose — this is not a general
  /// exception funnel; see the ~120 other `catch` blocks in this app that
  /// deliberately do not report here.
  Future<void> recordError(String errorCode) async {
    if (!_available) return;
    if (!_allowedErrorCodes.contains(errorCode)) return;
    await FirebaseCrashlytics.instance.recordError(
      'medicyn_error:$errorCode',
      null,
      fatal: false,
    );
  }

  /// Converts a count into a coarse bucket so product breadcrumbs never carry
  /// precise usage totals.
  static String countBucket(int count) {
    if (count <= 0) return 'none';
    if (count == 1) return 'one';
    if (count <= 5) return '2-5';
    return '6+';
  }

  static const _allowedKeys = {
    'method',
    'duration_bucket',
    'count_bucket',
    'permission_type',
    'result',
    'oem',
    'api_level',
    'error_code',
    'action',
    'lateness_bucket',
    'item_count_bucket',
    'status',
  };

  static const _allowedErrorCodes = {
    'timezone_unavailable',
    'invalid_schedule',
    'platform_schedule_failed',
    'notifications_blocked',
    'exact_alarm_unavailable',
    'sync_failed',
    'care_alert_failed',
  };

  static bool _isSafeValue(Object? value) {
    return value == null ||
        value is String && value.length <= 40 ||
        value is num ||
        value is bool;
  }
}
