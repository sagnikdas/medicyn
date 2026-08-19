import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data' show Int32List;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../data/local/database.dart';
import '../../data/local/tables.dart';
import 'notification_actions.dart';
import 'notification_ids.dart';

// v4: Bumped again to ensure sound and alarm settings are applied fresh.
// New channel ID forces a fresh channel with sound enabled for everyone.
const String reminderChannelId = 'dosely_reminders_v4';
const String reminderChannelName = 'Medicine Alarms';
const String reminderChannelDescription = 'Critical alerts for your medication schedule.';

/// A care alert is not an alarm and must not share the alarm channel: that
/// channel loops its sound until the notification is dismissed, which is right
/// for "take your tablet" and hostile for "your mother missed one". An ordinary
/// high-importance channel instead — it should be noticed, not obeyed.
///
/// Must match `CARE_ALERT_CHANNEL_ID` in
/// supabase/functions/notify-care/index.ts and the
/// `default_notification_channel_id` meta-data in AndroidManifest.xml. Android
/// silently drops a notification addressed to a channel that does not exist,
/// so a mismatch here produces no error anywhere — just no alert.
const String careAlertChannelId = 'dosely_care_alerts_v1';
const String careAlertChannelName = 'Care alerts';
const String careAlertChannelDescription =
    "When someone you're helping misses a dose.";

const String actionTaken = 'taken';
const String actionSnooze = 'snooze';

// Android's Notification.FLAG_INSISTENT: repeats the sound/vibration on loop
// until the notification is dismissed or tapped, instead of playing once.
const int _flagInsistent = 4;

/// The only thing that actually matters in this app: getting a notification
/// to fire, on time, whether or not the app is running.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Every-X-hours schedules keep this many upcoming doses armed at once.
  static const int _everyXHoursWindowDays = 14;
  static const int _everyXHoursMaxOccurrences = 120;

  Future<void> init() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    try {
      final deviceTz = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(deviceTz.identifier));
    } catch (_) {
      // Fallback to UTC if timezone lookup fails to prevent initialization crash
      tz.setLocalLocation(tz.getLocation('UTC'));
    }

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      requestCriticalPermission: true,
    );
    const settings = InitializationSettings(android: androidSettings, iOS: iosSettings);

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: handleNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
    await _createCareAlertChannel();
    _initialized = true;
  }

  /// Creates the care-alert channel up front rather than on first use.
  ///
  /// A push from the server can arrive before this device has ever shown a care
  /// alert itself, and Android drops a notification whose channel does not yet
  /// exist — so waiting until we need it means losing the first one, which is
  /// the one most likely to matter.
  Future<void> _createCareAlertChannel() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        careAlertChannelId,
        careAlertChannelName,
        description: careAlertChannelDescription,
        importance: Importance.high,
      ),
    );
  }

  /// The response for the notification that cold-launched the app, if any.
  /// `onDidReceiveNotificationResponse` only fires for taps that happen
  /// while the plugin is already listening (foreground, or backgrounded but
  /// alive) — a tap that launches the process from scratch is surfaced here
  /// instead, so callers should check this once at startup after [init].
  Future<NotificationResponse?> consumeLaunchNotificationResponse() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    return details?.notificationResponse;
  }

  Future<bool> requestPermissions() async {
    if (Platform.isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final granted = await ios?.requestPermissions(
        alert: true, 
        badge: true, 
        sound: true,
        critical: true,
      );
      return granted ?? false;
    }
    
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;

    final notifGranted = await android.requestNotificationsPermission() ?? false;
    final exactGranted = await android.requestExactAlarmsPermission() ?? false;
    
    // Request ignoring battery optimizations to prevent the OS from killing alarms
    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }

    return notifGranted && exactGranted;
  }

  NotificationDetails _details() => NotificationDetails(
        android: AndroidNotificationDetails(
          reminderChannelId,
          reminderChannelName,
          channelDescription: reminderChannelDescription,
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.alarm,
          playSound: true,
          enableVibration: true,
          fullScreenIntent: true,
          audioAttributesUsage: AudioAttributesUsage.alarm,
          visibility: NotificationVisibility.public,
          additionalFlags: Int32List.fromList(<int>[_flagInsistent]),
          actions: [
            AndroidNotificationAction(actionTaken, 'Taken', showsUserInterface: true),
            AndroidNotificationAction(actionSnooze, 'Snooze 10m', showsUserInterface: true),
          ],
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.critical,
        ),
      );

  tz.TZDateTime _nextInstanceOfTime(String hhmm, {int? weekday}) {
    final parts = hhmm.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    
    if (weekday != null) {
      final targetDartWeekday = weekday == 0 ? 7 : weekday;
      while (scheduled.weekday != targetDartWeekday || !scheduled.isAfter(now)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }
      return scheduled;
    }
    
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  String _title(Medicine m) =>
      m.strength.isEmpty ? m.drugName : '${m.drugName} ${m.strength}';

  String _body(Medicine m) => m.doseAmount.isEmpty ? 'Time for your dose' : 'Take ${m.doseAmount}';

  String _payload(String scheduleId, String timeLabel) =>
      jsonEncode({'scheduleId': scheduleId, 'timeLabel': timeLabel});

  /// [skipCancel] is for callers that have already cleared this schedule's
  /// alarms in a wider sweep — see [reconcile]. Cancelling costs a full
  /// `pendingNotificationRequests()` round-trip over the platform channel,
  /// which returns *every* armed alarm in the app, so repeating it per
  /// schedule is the difference between one such call and N+1 of them.
  Future<void> scheduleForScheduleWithMedicine(
    ScheduleWithMedicine sm, {
    bool skipCancel = false,
  }) async {
    await init();
    final schedule = sm.schedule;
    final medicine = sm.medicine;
    final frequency = FrequencyType.values.byName(schedule.frequencyType);

    if (!skipCancel) await cancelForSchedule(schedule);

    if (!schedule.active || frequency == FrequencyType.asNeeded) return;

    switch (frequency) {
      case FrequencyType.daily:
        for (final time in schedule.times) {
          await _plugin.zonedSchedule(
            id: notificationIdFor(schedule.id, time),
            title: _title(medicine),
            body: _body(medicine),
            scheduledDate: _nextInstanceOfTime(time),
            notificationDetails: _details(),
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            matchDateTimeComponents: DateTimeComponents.time,
            payload: _payload(schedule.id, time),
          );
        }
        break;

      case FrequencyType.specificDays:
        for (final day in schedule.daysOfWeek) {
          for (final time in schedule.times) {
            await _plugin.zonedSchedule(
              id: notificationIdFor(schedule.id, '$day-$time'),
              title: _title(medicine),
              body: _body(medicine),
              scheduledDate: _nextInstanceOfTime(time, weekday: day),
              notificationDetails: _details(),
              androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
              matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
              payload: _payload(schedule.id, time),
            );
          }
        }
        break;

      case FrequencyType.everyXHours:
        final interval = schedule.intervalHours ?? 8;
        final anchorTime = schedule.times.isNotEmpty ? schedule.times.first : '08:00';
        
        // Correct every-X-hours logic: find the first occurrence in the sequence (anchor + N*interval)
        // that is in the future, instead of just skipping to tomorrow.
        final parts = anchorTime.split(':');
        final anchorHour = int.parse(parts[0]);
        final anchorMinute = int.parse(parts[1]);
        final now = tz.TZDateTime.now(tz.local);
        
        var next = tz.TZDateTime(tz.local, now.year, now.month, now.day, anchorHour, anchorMinute);
        
        // Shift back to start of sequence if needed to cover today's missed slots
        while (next.isAfter(now)) {
          final prev = next.subtract(Duration(hours: interval));
          if (prev.isBefore(now)) break;
          next = prev;
        }
        
        // Ensure 'next' is actually in the future
        while (!next.isAfter(now)) {
          next = next.add(Duration(hours: interval));
        }

        final windowEnd = now.add(Duration(days: _everyXHoursWindowDays));
        var index = 0;
        while (next.isBefore(windowEnd) && index < _everyXHoursMaxOccurrences) {
          await _plugin.zonedSchedule(
            id: notificationIdFor(schedule.id, 'slot-$index'),
            title: _title(medicine),
            body: _body(medicine),
            scheduledDate: next,
            notificationDetails: _details(),
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            payload: _payload(schedule.id, anchorTime),
          );
          next = next.add(Duration(hours: interval));
          index++;
        }
        break;

      case FrequencyType.asNeeded:
        break;
    }
  }

  /// Cancels every currently-armed alarm belonging to [schedule] — not just
  /// the ones its *current* times/days would recompute. Recomputing ids from
  /// the schedule's present state (the old approach) silently orphans any
  /// alarm armed under a time that's since been edited or removed, since
  /// that id is never regenerated to be cancelled; recurring "daily"/
  /// "specificDays" alarms then keep firing forever. Matching against each
  /// pending notification's actual payload instead — see [_cancelWhere] —
  /// finds whatever is really armed regardless of how it got that id,
  /// which also naturally cancels any outstanding snooze one-off.
  Future<void> cancelForSchedule(Schedule schedule) async {
    await init();
    await _cancelWhere((scheduleId) => scheduleId == schedule.id);
  }

  /// Cancels every pending notification whose payload's `scheduleId`
  /// satisfies [shouldCancel]. Payloads without a decodable `scheduleId`
  /// (there shouldn't be any, but a plugin-internal or malformed one isn't
  /// impossible) are left alone rather than guessed at.
  Future<void> _cancelWhere(bool Function(String scheduleId) shouldCancel) async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final request in pending) {
      final payload = request.payload;
      if (payload == null || payload.isEmpty) continue;
      String? scheduleId;
      try {
        scheduleId = (jsonDecode(payload) as Map<String, dynamic>)['scheduleId'] as String?;
      } catch (_) {
        continue;
      }
      if (scheduleId != null && shouldCancel(scheduleId)) {
        await _plugin.cancel(id: request.id);
      }
    }
  }

  Future<void> scheduleSnooze({
    required String scheduleId,
    required String title,
    required String body,
    required Duration delay,
  }) async {
    await init();
    await _plugin.zonedSchedule(
      id: notificationIdFor(scheduleId, 'snooze-${DateTime.now().millisecondsSinceEpoch}'),
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.now(tz.local).add(delay),
      notificationDetails: _details(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: _payload(scheduleId, 'snooze'),
    );
  }

  /// Shows a care alert this device received while in the foreground.
  ///
  /// Only needed for the foreground: Android draws an FCM notification message
  /// itself when the app is backgrounded or dead, and deliberately does not
  /// when it is in front of the user. Without this, a caregiver sitting in the
  /// app is the one person who never hears that a dose was missed.
  ///
  /// [patientId] rides along in the payload so a tap opens the right feed —
  /// see `handleNotificationResponse`.
  Future<void> showCareAlert({
    required String title,
    required String body,
    String? patientId,
  }) async {
    await init();
    await _plugin.show(
      // A fresh id per alert, so a second missed dose does not overwrite the
      // first while the caregiver is reading it.
      id: DateTime.now().millisecondsSinceEpoch.remainder(1 << 31),
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          careAlertChannelId,
          careAlertChannelName,
          channelDescription: careAlertChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.message,
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      ),
      payload: jsonEncode({'careAlertPatientId': patientId}),
    );
  }

  /// Re-arms every active schedule and, first, sweeps away any armed alarm
  /// that doesn't belong to one — the general-purpose fix for the same
  /// staleness [cancelForSchedule] targets for a single schedule: an alarm
  /// orphaned by an edited time, a delete whose cancel didn't fully land, or
  /// any other drift between what's armed and what the database says should
  /// be. Runs on every app foreground (see `HomeScreen`'s lifecycle
  /// observer), so the device self-heals without needing a fresh install.
  Future<void> reconcile(AppDatabase db) async {
    await init();
    final active = await db.activeSchedulesOnce();
    // One sweep clears everything: alarms belonging to no active schedule
    // (orphans) and alarms belonging to one that's about to be re-armed
    // below. Doing both here is what lets the per-schedule calls skip their
    // own cancel pass — see [scheduleForScheduleWithMedicine].
    await _cancelWhere((_) => true);
    for (final sm in active) {
      await scheduleForScheduleWithMedicine(sm, skipCancel: true);
    }
  }
}
