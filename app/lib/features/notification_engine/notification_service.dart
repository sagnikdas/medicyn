import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../data/local/database.dart';
import '../../data/local/tables.dart';
import 'notification_actions.dart';
import 'notification_ids.dart';

const String reminderChannelId = 'dosely_reminders';
const String reminderChannelName = 'Medicine reminders';
const String reminderChannelDescription = 'Alerts you when it\'s time to take a dose.';

const String actionTaken = 'taken';
const String actionSnooze = 'snooze';

/// The only thing that actually matters in this app: getting a notification
/// to fire, on time, whether or not the app is running. Everything else
/// (capture, AI parsing, review) just produces the data this service acts on.
///
/// - `daily` / `specificDays` schedules use the plugin's native recurrence
///   (`matchDateTimeComponents`), so a single `zonedSchedule` call keeps
///   firing indefinitely without the app needing to run again.
/// - `everyXHours` schedules have no native recurrence primitive, so a
///   rolling window of discrete alarms is (re)scheduled on init and on every
///   app foreground via [reconcile] — see notionally "top up the window".
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
    final deviceTz = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(deviceTz.identifier));

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: handleNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
    _initialized = true;
  }

  Future<bool> requestPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    final notifGranted = await android.requestNotificationsPermission() ?? false;
    final exactGranted = await android.requestExactAlarmsPermission() ?? false;
    return notifGranted && exactGranted;
  }

  Future<bool> hasExactAlarmPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.canScheduleExactNotifications() ?? true;
  }

  NotificationDetails _details() => const NotificationDetails(
        android: AndroidNotificationDetails(
          reminderChannelId,
          reminderChannelName,
          channelDescription: reminderChannelDescription,
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
          actions: [
            AndroidNotificationAction(actionTaken, 'Taken'),
            AndroidNotificationAction(actionSnooze, 'Snooze 10m'),
          ],
        ),
      );

  tz.TZDateTime _nextInstanceOfTime(String hhmm, {int? weekday}) {
    final parts = hhmm.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (weekday != null) {
      // Dart weekday: Monday=1..Sunday=7. Our daysOfWeek: Sunday=0..Saturday=6.
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

  /// Cancels and reschedules every alarm for one schedule. IDs are
  /// deterministic (see [notificationIdFor]), so calling this repeatedly is
  /// always safe and idempotent.
  Future<void> scheduleForScheduleWithMedicine(ScheduleWithMedicine sm) async {
    await init();
    final schedule = sm.schedule;
    final medicine = sm.medicine;
    final frequency = FrequencyType.values.byName(schedule.frequencyType);

    await cancelForSchedule(schedule);

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
        var next = _nextInstanceOfTime(anchorTime);
        final windowEnd = tz.TZDateTime.now(tz.local).add(Duration(days: _everyXHoursWindowDays));
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

  Future<void> cancelForSchedule(Schedule schedule) async {
    await init();
    final frequency = FrequencyType.values.byName(schedule.frequencyType);
    switch (frequency) {
      case FrequencyType.daily:
        for (final time in schedule.times) {
          await _plugin.cancel(id: notificationIdFor(schedule.id, time));
        }
        break;
      case FrequencyType.specificDays:
        for (final day in schedule.daysOfWeek) {
          for (final time in schedule.times) {
            await _plugin.cancel(id: notificationIdFor(schedule.id, '$day-$time'));
          }
        }
        break;
      case FrequencyType.everyXHours:
        for (var i = 0; i < _everyXHoursMaxOccurrences; i++) {
          await _plugin.cancel(id: notificationIdFor(schedule.id, 'slot-$i'));
        }
        break;
      case FrequencyType.asNeeded:
        break;
    }
  }

  /// Schedules a single one-off reminder N minutes from now — used by the
  /// "Snooze" notification action.
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

  /// Re-arms every active schedule. Cheap and idempotent (deterministic
  /// IDs), so it's safe to call on every app start/foreground — this is the
  /// mitigation for OEMs that silently drop alarms in the background: as
  /// long as the user opens the app occasionally, everything self-heals.
  Future<void> reconcile(AppDatabase db) async {
    await init();
    final active = await db.activeSchedulesOnce();
    for (final sm in active) {
      await scheduleForScheduleWithMedicine(sm);
    }
  }
}
