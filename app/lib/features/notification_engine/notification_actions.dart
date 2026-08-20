import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../core/app_navigation.dart';
import '../../core/ids.dart';
import '../../data/local/database.dart';
import '../../data/local/tables.dart';
import '../care/dose_feed_screen.dart';
import '../care/phone_dial.dart';
import '../dose_confirm/dose_confirm_screen.dart';
import 'notification_service.dart';

/// Runs in a separate background isolate when the user taps a notification
/// action while the app isn't in the foreground. Per flutter_local_notifications'
/// documented pattern, the Flutter binding must be (re)initialized before
/// touching any platform channel (path_provider, sqlite, etc).
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  WidgetsFlutterBinding.ensureInitialized();
  handleNotificationResponse(response);
}

/// Shared by both the foreground and background entry points. For action
/// buttons (Taken/Snooze), opens its own short-lived database connection
/// rather than relying on an app-wide singleton, since a background isolate
/// has none of the app's state. For a plain tap on the notification body,
/// pushes [DoseConfirmScreen] instead — which does the same on its own.
void handleNotificationResponse(NotificationResponse response) async {
  final actionId = response.actionId;

  final payloadRaw = response.payload;
  if (payloadRaw == null || payloadRaw.isEmpty) return;
  // This runs from a plugin callback, often on a background isolate with no
  // error reporting attached, so a malformed payload must not throw: an
  // uncaught exception here is invisible and takes the Taken/Snooze action
  // with it. The payloads we write are always well-formed JSON, but a
  // notification left over from an older build (or one the plugin surfaces
  // itself) needn't be.
  final Map<String, dynamic> payload;
  try {
    payload = jsonDecode(payloadRaw) as Map<String, dynamic>;
  } catch (_) {
    return;
  }
  // A care alert — "someone you help missed a dose" — is not about a schedule
  // of this device's own, so it is routed before the scheduleId check below
  // rather than being dropped by it. Only the foreground path produces one
  // (see NotificationService.showCareAlert); a push that Android drew itself
  // is tapped through FirebaseMessaging instead.
  final careAlertPatientId = payload['careAlertPatientId'] as String?;
  if (careAlertPatientId != null && careAlertPatientId.isNotEmpty) {
    if (actionId == actionCareCall) {
      final phone = payload['careAlertCallPhone'] as String?;
      final dialable = dialablePhone(phone);
      if (dialable != null) {
        unawaited(openDialer(dialable));
      }
      return;
    }
    openFeedForPatient(careAlertPatientId);
    return;
  }

  final scheduleId = payload['scheduleId'] as String?;
  if (scheduleId == null) return;
  // The dose was due whenever the alarm was set for — not whenever the user
  // got around to responding, which can be minutes (or longer) later.
  // `timeLabel` carries the real "HH:mm" for daily/specific-days reminders;
  // snoozed and every-X-hours notifications don't carry a meaningful clock
  // time here, so those fall back to now.
  final scheduledAt = _scheduledAtFromTimeLabel(payload['timeLabel'] as String?) ?? DateTime.now();

  if (actionId != actionTaken && actionId != actionSnooze) {
    // Plain tap on the notification body (not an action button) — bring up
    // the Taken/Snooze prompt. Only reachable with a live widget tree
    // (foreground, or backgrounded-but-alive): a cold start's launch tap is
    // handled separately via NotificationService.consumeLaunchNotificationResponse,
    // since no navigator exists yet when this fires on a background isolate.
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => DoseConfirmScreen(
          scheduleId: scheduleId,
          scheduledAt: scheduledAt,
          db: AppDatabase(),
        ),
      ),
    );
    return;
  }

  final db = AppDatabase();
  try {
    if (actionId == actionTaken) {
      await recordDoseTaken(db, scheduleId: scheduleId, scheduledAt: scheduledAt);
      return;
    }
    await recordDoseSnoozed(db, scheduleId: scheduleId, scheduledAt: scheduledAt);
  } finally {
    await db.close();
  }
}

Future<void> recordDoseTaken(
  AppDatabase db, {
  required String scheduleId,
  required DateTime scheduledAt,
}) async {
  await db.recordDoseAction(
    id: newUuid(),
    scheduleId: scheduleId,
    scheduledAt: scheduledAt,
    action: DoseAction.taken,
  );
  await db.decrementStockForSchedule(scheduleId);
}

/// Logs the snooze, then arms a one-off reminder [delay] out.
Future<void> recordDoseSnoozed(
  AppDatabase db, {
  required String scheduleId,
  required DateTime scheduledAt,
  Duration delay = const Duration(minutes: 10),
}) async {
  await db.recordDoseAction(
    id: newUuid(),
    scheduleId: scheduleId,
    scheduledAt: scheduledAt,
    action: DoseAction.snoozed,
  );
  final schedule = await db.scheduleById(scheduleId);
  if (schedule == null) return;
  final medicine = await db.medicineById(schedule.medicineId);
  if (medicine == null) return;

  await NotificationService.instance.scheduleSnooze(
    scheduleId: scheduleId,
    medicine: medicine,
    delay: delay,
  );
}

/// Parses a "HH:mm" time label into today's occurrence of that clock time.
/// Returns null for anything that isn't a plain "HH:mm" — notably the
/// literal string `'snooze'` used by [NotificationService.scheduleSnooze],
/// and the every-X-hours anchor time, which doesn't represent this specific
/// occurrence's actual fire time.
DateTime? _scheduledAtFromTimeLabel(String? timeLabel) {
  if (timeLabel == null) return null;
  final match = RegExp(r'^([0-2][0-9]):([0-5][0-9])$').firstMatch(timeLabel);
  if (match == null) return null;
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  if (hour > 23) return null;
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, hour, minute);
}
