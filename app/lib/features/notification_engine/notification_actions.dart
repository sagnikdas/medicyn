import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../core/app_navigation.dart';
import '../../data/local/database.dart';
import '../../data/local/tables.dart';
import '../care/dose_feed_screen.dart';
import '../care/phone_dial.dart';
import '../dose_confirm/dose_confirm_screen.dart';
import 'missed_doses.dart';
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
///
/// Returns a [Future] (rather than plain `void`) so main.dart's cold-start
/// launch path can await it before marking that launch handled — a
/// void-returning function is still a valid
/// `onDidReceiveNotificationResponse`/background callback, so neither of
/// those two callers has to change.
Future<void> handleNotificationResponse(NotificationResponse response) async {
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
  final scheduledAt = _scheduledAtFromPayload(payload) ?? DateTime.now();

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

/// Records the dose as taken, once per occurrence however many times the
/// button is pressed.
///
/// The id is derived from the schedule and the due time rather than minted
/// fresh, so a second tap updates the row the first one wrote. With a random
/// id, two taps on the same reminder wrote two Taken rows *and* took two
/// tablets off the bottle.
Future<void> recordDoseTaken(
  AppDatabase db, {
  required String scheduleId,
  required DateTime scheduledAt,
  String source = 'notification',
}) async {
  // Nothing decrements the medicine's stock count here — it is derived from
  // this log at display time (see derivedTabletsRemaining), so a caregiver's
  // concurrent edit to the reminder can never revert a dose this device just
  // took. Repeated taps don't need an `alreadyRecorded` guard either, for
  // the same reason: there's no decrement left to double-count. recordDoseAction
  // is a plain insertOnConflictUpdate, so a second tap just rewrites the same
  // fact — the deterministic id below is what keeps it one row.
  await db.recordDoseAction(
    id: doseLogIdFor(scheduleId, scheduledAt, DoseAction.taken),
    scheduleId: scheduleId,
    scheduledAt: scheduledAt,
    action: DoseAction.taken,
    source: source,
  );
}

/// Logs the snooze, then arms a one-off reminder [delay] out.
///
/// Both halves are keyed to the dose rather than to the tap. Pressing Snooze
/// repeatedly used to write a history row per press and arm an *additional*
/// alarm per press, so five presses meant five lines in the feed and five
/// reminders going off ten minutes later. Now the row is updated in place —
/// which also restarts the snooze window, since the latest press is when the
/// person actually asked to be left alone — and the alarm replaces the one
/// before it.
Future<void> recordDoseSnoozed(
  AppDatabase db, {
  required String scheduleId,
  required DateTime scheduledAt,
  Duration delay = MissedDoseDetector.snoozeWindow,
}) async {
  await db.recordDoseAction(
    id: doseLogIdFor(scheduleId, scheduledAt, DoseAction.snoozed),
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
    scheduledAt: scheduledAt,
  );
}

/// When the dose this notification is about was due.
///
/// Prefers `scheduledAt`, which every alarm this build arms carries: it names
/// the exact occurrence, so answering a snoozed reminder is attributed to the
/// dose that was snoozed, and answering the 16:00 slot of an every-X-hours
/// schedule is not attributed to its 08:00 anchor.
///
/// Falls back to parsing `timeLabel` for notifications armed by an earlier
/// build, which are still sitting in Android's alarm table after an update.
DateTime? _scheduledAtFromPayload(Map<String, dynamic> payload) {
  final raw = payload['scheduledAt'] as String?;
  if (raw != null && raw.isNotEmpty) {
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) return parsed.toLocal();
  }
  return _scheduledAtFromTimeLabel(payload['timeLabel'] as String?);
}

/// Parses a "HH:mm" time label into today's occurrence of that clock time.
/// Returns null for anything that isn't a plain "HH:mm".
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
