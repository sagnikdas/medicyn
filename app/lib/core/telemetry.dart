import 'package:sentry_flutter/sentry_flutter.dart';

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

  Future<void> record(
    MedicynEvent event, {
    Map<String, Object?> properties = const {},
  }) async {
    final safe = <String, Object?>{};
    for (final entry in properties.entries) {
      if (_allowedKeys.contains(entry.key) && _isSafeValue(entry.value)) {
        safe[entry.key] = entry.value;
      }
    }
    await Sentry.addBreadcrumb(
      Breadcrumb(
        category: 'medicyn.product',
        type: 'info',
        message: event.name,
        data: safe,
      ),
    );
  }

  Future<void> recordError(String errorCode) async {
    if (!_allowedErrorCodes.contains(errorCode)) return;
    await Sentry.captureMessage(
      'medicyn_error:$errorCode',
      level: SentryLevel.error,
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

/// Removes user identity and arbitrary extras before a Sentry event leaves
/// the device. Breadcrumbs are retained only after their data has passed the
/// typed allow-list above.
SentryEvent? redactSentryEvent(SentryEvent event, Hint hint) {
  event.user = null;
  event.request = null;
  // `extra` is deprecated in Sentry but clearing it is still necessary for
  // older SDK integrations that attach arbitrary request data.
  // ignore: deprecated_member_use
  event.extra?.clear();
  event.breadcrumbs = event.breadcrumbs
      ?.map(
        (crumb) => Breadcrumb(
          timestamp: crumb.timestamp,
          type: crumb.type,
          level: crumb.level,
          category: crumb.category,
          message: crumb.message,
          data: {
            for (final entry
                in crumb.data?.entries ?? <MapEntry<String, Object?>>[])
              if (MedicynTelemetry._allowedKeys.contains(entry.key) &&
                  MedicynTelemetry._isSafeValue(entry.value))
                entry.key: entry.value,
          },
        ),
      )
      .toList(growable: false);
  return event;
}
