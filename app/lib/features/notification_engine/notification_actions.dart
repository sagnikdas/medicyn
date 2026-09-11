import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../core/app_navigation.dart';
import '../../core/app_settings.dart';
import '../../data/local/database.dart';
import '../../data/local/lifecycle.dart';
import '../../data/local/tables.dart';
import '../care/dose_feed_screen.dart';
import '../care/phone_dial.dart';
import '../reminders_home/today_care_events.dart';
import 'missed_doses.dart';
import 'notification_service.dart';

/// Foreground screens do not receive Drift invalidation from the short-lived
/// database connection used by notification taps. This event bridges that
/// gap immediately; the database row remains the source of truth for later
/// rebuilds and background-isolate actions.
final doseResponseEvents = ValueNotifier<DoseResponseEvent?>(null);

class DoseResponseEvent {
  const DoseResponseEvent({
    required this.scheduleId,
    required this.scheduledAt,
    required this.action,
  });

  final String scheduleId;
  final DateTime scheduledAt;
  final DoseAction action;
}

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
/// brings the app to its root instead — see the branch below — and lets
/// Home's own attention detection show the same bold Taken/Snooze dialog it
/// already shows for any due dose.
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

  final todayCareId = payload[todayCarePayloadKey];
  if (todayCareId is String && todayCareId.isNotEmpty) {
    openTodayCareReminder(todayCareId);
    return;
  }

  final scheduleId = payload['scheduleId'] as String?;
  if (scheduleId == null) return;
  // The dose was due whenever the alarm was set for — not whenever the user
  // got around to responding, which can be minutes (or longer) later.
  final scheduledAt = _scheduledAtFromPayload(payload) ?? DateTime.now();

  if (actionId != actionTaken && actionId != actionSnooze) {
    // Plain tap on the notification body (not an action button). Dismiss
    // whatever screen was open before this — responding to the reminder
    // takes priority — so Home (kept mounted underneath every route) is
    // current again and its own attention detection can show the bold
    // Taken/Snooze dialog immediately, reading the same due dose straight
    // from the database rather than needing scheduleId/scheduledAt threaded
    // through a dedicated confirm screen the way an earlier build did.
    // `scheduleId`/`scheduledAt` above still matter for the action-button
    // branches below.
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
    return;
  }

  final db = AppDatabase();
  try {
    if (actionId == actionTaken) {
      await recordDoseTaken(
        db,
        scheduleId: scheduleId,
        scheduledAt: scheduledAt,
      );
      return;
    }
    await recordDoseSnoozed(
      db,
      scheduleId: scheduleId,
      scheduledAt: scheduledAt,
    );
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
  // Taking a dose — whether ahead of its own alarm or after it already
  // rang — must stop that occurrence's alarm(s) from ringing again, and
  // must not leave a pending snooze one-off behind either. A full re-arm
  // does both: see _rescheduleAfterSettle.
  await _rescheduleAfterSettle(db, scheduleId);
}

/// Logs a PRN ("as needed") dose the moment someone taps "Log now" on its
/// card. An as-needed medicine has no schedule to generate occurrences from
/// (see [expectedDoses]), so there is no pre-existing `scheduledAt` to log
/// against the way a due reminder has — the tap itself *is* the occurrence,
/// so [at] (defaulting to now) is used as both.
///
/// Deliberately just a thin wrapper around [recordDoseTaken] rather than a
/// parallel write path: an as-needed dose has to land in the same
/// `dose_logs` table, decrement stock, and sync the same way a scheduled
/// dose does, so it shows up identically in dose history, the calendar and
/// exports. [_rescheduleAfterSettle] (run inside [recordDoseTaken]) is a
/// no-op for an as-needed schedule — [FrequencyType.asNeeded] has nothing to
/// arm — so this never risks scheduling a phantom alarm for a medicine that
/// has no fixed times.
Future<void> recordAsNeededDoseTaken(
  AppDatabase db, {
  required String scheduleId,
  DateTime? at,
  String source = 'manual',
}) {
  final loggedAt = at ?? DateTime.now();
  return recordDoseTaken(
    db,
    scheduleId: scheduleId,
    scheduledAt: loggedAt,
    source: source,
  );
}

/// Cancels and re-arms one schedule's alarms from scratch, now that a dose
/// has just been settled (Taken or Snoozed).
///
/// A fresh full re-arm — rather than trying to cancel just the one pending
/// notification that was answered — is what correctly retires today's
/// occurrence while keeping a daily/specificDays schedule's alarm intact for
/// its next one. flutter_local_notifications reschedules that alarm from
/// its own native fire handler without ever refreshing its payload, so
/// targeting a specific pending request by payload risks matching (or
/// missing) the wrong instance once that payload has gone stale — a
/// schedule that hasn't been reconciled today, say. `cancelForSchedule`
/// instead matches on the schedule id alone, which is never stale, and the
/// re-arm that follows both skips any occurrence already logged Taken (see
/// NotificationService.scheduleForScheduleWithMedicine) and — since "now" is
/// already past a dose that was due enough to answer — naturally resolves
/// to the next occurrence for one that was only Snoozed.
///
/// No-ops quietly if the schedule or medicine can no longer be found (the
/// medicine was deleted moments after this dose was answered, say) — there
/// is nothing left to re-arm, and cancelForSchedule already ran when the
/// medicine/schedule was deleted.
Future<void> _rescheduleAfterSettle(AppDatabase db, String scheduleId) async {
  final schedule = await db.scheduleById(scheduleId);
  if (schedule == null) return;
  final medicine = await db.medicineById(schedule.medicineId);
  if (medicine == null) return;
  try {
    await NotificationService.instance.scheduleForScheduleWithMedicine(
      ScheduleWithMedicine(schedule, medicine),
      db: db,
    );
  } catch (_) {
    // Best-effort: the dose action is already persisted, and the next
    // foreground's reconcile picks this schedule back up regardless.
  }
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
  Duration? delay,
}) async {
  // Notification actions can run in a background isolate, where the app
  // startup path has not loaded preferences yet. Resolve the configured
  // duration here so tray actions and in-app actions behave identically.
  if (delay == null) await AppSettings.instance.init();
  final effectiveDelay =
      delay ?? Duration(minutes: AppSettings.instance.snoozeMinutes);
  await db.recordDoseAction(
    id: doseLogIdFor(scheduleId, scheduledAt, DoseAction.snoozed),
    scheduleId: scheduleId,
    scheduledAt: scheduledAt,
    action: DoseAction.snoozed,
  );
  // A Taken response can arrive just before a delayed Snooze callback. Keep
  // the audit facts, but never arm a re-reminder for a dose already settled.
  if (await db.doseLogById(
        doseLogIdFor(scheduleId, scheduledAt, DoseAction.taken),
      ) !=
      null) {
    await NotificationService.instance.cancelSnooze(
      scheduleId: scheduleId,
      scheduledAt: scheduledAt,
    );
    return;
  }
  doseResponseEvents.value = DoseResponseEvent(
    scheduleId: scheduleId,
    scheduledAt: scheduledAt,
    action: DoseAction.snoozed,
  );
  final schedule = await db.scheduleById(scheduleId);
  if (schedule == null) return;
  final medicine = await db.medicineById(schedule.medicineId);
  if (medicine == null) return;

  // Retire today's regular alarm(s) before arming the one-off below — see
  // _rescheduleAfterSettle. Order matters here: that re-arm's own cancel
  // sweep would wipe out the snooze this method is about to arm if it ran
  // after it instead of before.
  await _rescheduleAfterSettle(db, scheduleId);

  // Re-check freshness right before arming: `schedule` above was loaded
  // before _rescheduleAfterSettle's own awaited plugin calls, so someone
  // deleting or stopping this medicine in that window would otherwise be
  // invisible here — arming the snooze regardless resurrected a reminder
  // for a medicine that no longer exists, ringing on a phone with nothing
  // left to say it was for.
  final current = await db.scheduleById(scheduleId);
  if (current == null || !reminderIsActive(current)) return;

  await NotificationService.instance.scheduleSnooze(
    scheduleId: scheduleId,
    medicine: medicine,
    delay: effectiveDelay,
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
