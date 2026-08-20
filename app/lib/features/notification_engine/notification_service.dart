import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data' show Int32List;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../core/app_settings.dart';
import '../../data/local/database.dart';
import '../../data/local/tables.dart';
import 'notification_actions.dart';
import 'notification_ids.dart';
import 'schedule_validation.dart';

// v4: Bumped again to ensure sound and alarm settings are applied fresh.
// New channel ID forces a fresh channel with sound enabled for everyone.
const String reminderChannelId = 'dosely_reminders_v4';
const String reminderChannelName = 'Medicine Alarms';
const String reminderChannelDescription =
    'Critical alerts for your medication schedule.';

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

const String _redactedReminderTitle = 'Medicine reminder';
const String _redactedReminderBody = 'Time to take your dose';

/// Care alerts default to private: the recipient does not need the drug name
/// on a locked phone. Unlike the patient's own reminder, there is no opt-in
/// to show it — a care alert is not something you act on through the lock
/// screen. Must match the FCM `visibility: "PRIVATE"` in
/// `supabase/functions/notify-care/fcm.ts`, which is the path Android draws
/// itself when the app is backgrounded or dead.
const NotificationVisibility careAlertLockScreenVisibility =
    NotificationVisibility.private;

/// Title, body and lock-screen visibility for a medicine reminder.
///
/// A locked phone is readable by anyone in the room, so the named copy is
/// only used when the user has opted in. Kept as a top-level function so
/// the redacted vs named strings can be tested without the notification
/// plugin.
({String title, String body, NotificationVisibility visibility})
reminderLockScreenCopy({
  required bool showMedicineOnLockScreen,
  required String drugName,
  required String strength,
  required String doseAmount,
}) {
  if (!showMedicineOnLockScreen) {
    return (
      title: _redactedReminderTitle,
      body: _redactedReminderBody,
      visibility: NotificationVisibility.private,
    );
  }
  return (
    title: strength.isEmpty ? drugName : '$drugName $strength',
    body: doseAmount.isEmpty ? 'Time for your dose' : 'Take $doseAmount',
    visibility: NotificationVisibility.public,
  );
}

// Android's Notification.FLAG_INSISTENT: repeats the sound/vibration on loop
// until the notification is dismissed or tapped, instead of playing once.
const int _flagInsistent = 4;

/// The only thing that actually matters in this app: getting a notification
/// to fire, on time, whether or not the app is running.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Every-X-hours schedules keep this many upcoming doses armed at once.
  static const int _everyXHoursWindowDays = 14;
  static const int _everyXHoursMaxOccurrences = 120;

  /// Seven would do — the eighth step is slack so a schedule whose weekday
  /// is valid but whose time has already passed today still resolves.
  static const int _maxWeekdaySearchDays = 8;

  /// A ceiling on the walk that finds the first every-X-hours slot. With an
  /// interval validated to 1..24 the walk covers at most a day either way, so
  /// this is unreachable in practice and exists only to make the loop
  /// provably finite.
  static const int _everyXHoursMaxSearchSteps = 64;

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

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      requestCriticalPermission: true,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

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
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
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
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final granted = await ios?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
        critical: true,
      );
      return granted ?? false;
    }

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return true;

    final notifGranted =
        await android.requestNotificationsPermission() ?? false;
    final exactGranted = await android.requestExactAlarmsPermission() ?? false;

    // Request ignoring battery optimizations to prevent the OS from killing alarms
    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }

    return notifGranted && exactGranted;
  }

  NotificationDetails _details({required NotificationVisibility visibility}) =>
      NotificationDetails(
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
          visibility: visibility,
          additionalFlags: Int32List.fromList(<int>[_flagInsistent]),
          actions: [
            AndroidNotificationAction(
              actionTaken,
              'Taken',
              showsUserInterface: true,
            ),
            AndroidNotificationAction(
              actionSnooze,
              'Snooze 10m',
              showsUserInterface: true,
            ),
          ],
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.critical,
        ),
      );

  /// Reads the lock-screen setting at schedule time. Android stores title,
  /// body and visibility on the alarm itself, so a later toggle only
  /// takes effect after the next reconcile.
  Future<({String title, String body, NotificationVisibility visibility})>
  _copyFor(Medicine medicine) async {
    await AppSettings.instance.init();
    return reminderLockScreenCopy(
      showMedicineOnLockScreen: AppSettings.instance.showMedicineOnLockScreen,
      drugName: medicine.drugName,
      strength: medicine.strength,
      doseAmount: medicine.doseAmount,
    );
  }

  /// The next occurrence of [time], optionally on a specific [weekday]
  /// (0 = Sunday, matching the stored convention).
  ///
  /// Returns null rather than throwing or spinning when no occurrence can be
  /// found. [schedulableDays] should already have ruled that out, so a null
  /// here means something got past it — and the one thing this must never do
  /// is fail to return, because [reconcile] has already cancelled the
  /// device's alarms by the time it calls this.
  tz.TZDateTime? _nextInstanceOfTime(ClockTime time, {int? weekday}) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );

    if (weekday != null) {
      final targetDartWeekday = weekday == 0 ? 7 : weekday;
      // A matching weekday is always within seven steps, so this bound is
      // never reached for a value in 0..6. It is here so that one that is
      // not — `9`, say, which no `DateTime.weekday` equals — costs this
      // schedule and nothing else.
      for (var i = 0; i <= _maxWeekdaySearchDays; i++) {
        if (scheduled.weekday == targetDartWeekday && scheduled.isAfter(now)) {
          return scheduled;
        }
        scheduled = scheduled.add(const Duration(days: 1));
      }
      return null;
    }

    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

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

    // `byName` throws on a string that is not one of the enum's names, and a
    // `frequencyType` arrives from the same three unvalidated sources as the
    // fields below. Treat an unrecognised one as unschedulable rather than
    // letting it abort a caller that has already cancelled the alarms.
    FrequencyType? frequency;
    for (final candidate in FrequencyType.values) {
      if (candidate.name == schedule.frequencyType) {
        frequency = candidate;
        break;
      }
    }
    if (frequency == null) {
      throw UnschedulableSchedule(
        schedule.id,
        'unknown frequencyType "${schedule.frequencyType}"',
      );
    }

    if (!skipCancel) await cancelForSchedule(schedule);

    if (!schedule.active || frequency == FrequencyType.asNeeded) return;

    final times = schedulableTimes(schedule.times);
    final copy = await _copyFor(medicine);
    final details = _details(visibility: copy.visibility);

    switch (frequency) {
      case FrequencyType.daily:
        for (final time in times) {
          final when = _nextInstanceOfTime(time.clock);
          if (when == null) continue;
          await _plugin.zonedSchedule(
            id: notificationIdFor(schedule.id, time.label),
            title: copy.title,
            body: copy.body,
            scheduledDate: when,
            notificationDetails: details,
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            matchDateTimeComponents: DateTimeComponents.time,
            payload: _payload(schedule.id, time.label),
          );
        }
        break;

      case FrequencyType.specificDays:
        for (final day in schedulableDays(schedule.daysOfWeek)) {
          for (final time in times) {
            final when = _nextInstanceOfTime(time.clock, weekday: day);
            if (when == null) continue;
            await _plugin.zonedSchedule(
              id: notificationIdFor(schedule.id, '$day-${time.label}'),
              title: copy.title,
              body: copy.body,
              scheduledDate: when,
              notificationDetails: details,
              androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
              matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
              payload: _payload(schedule.id, time.label),
            );
          }
        }
        break;

      case FrequencyType.everyXHours:
        final interval = schedulableIntervalHours(schedule.intervalHours);
        if (interval == null) {
          throw UnschedulableSchedule(
            schedule.id,
            'intervalHours ${schedule.intervalHours} is outside 1..24',
          );
        }

        // The anchor is the first *parseable* time, not simply the first —
        // a malformed entry ahead of a good one should not decide the
        // sequence, and should not fall back to 08:00 while a real time sits
        // behind it.
        final anchor = times.isNotEmpty
            ? times.first
            : (label: '08:00', clock: (hour: 8, minute: 0));
        final now = tz.TZDateTime.now(tz.local);

        var next = tz.TZDateTime(
          tz.local,
          now.year,
          now.month,
          now.day,
          anchor.clock.hour,
          anchor.clock.minute,
        );

        // Walk back to the start of today's sequence so a slot already past
        // is still covered, then forward to the first one still ahead. Both
        // walks move by a whole interval, which validation has guaranteed is
        // at least an hour, so both terminate; the step ceilings are there
        // for the case where that guarantee is ever weakened.
        var steps = 0;
        while (next.isAfter(now) && steps++ < _everyXHoursMaxSearchSteps) {
          final prev = next.subtract(Duration(hours: interval));
          if (prev.isBefore(now)) break;
          next = prev;
        }

        steps = 0;
        while (!next.isAfter(now) && steps++ < _everyXHoursMaxSearchSteps) {
          next = next.add(Duration(hours: interval));
        }
        if (!next.isAfter(now)) break;

        final windowEnd = now.add(Duration(days: _everyXHoursWindowDays));
        var index = 0;
        while (next.isBefore(windowEnd) && index < _everyXHoursMaxOccurrences) {
          await _plugin.zonedSchedule(
            id: notificationIdFor(schedule.id, 'slot-$index'),
            title: copy.title,
            body: copy.body,
            scheduledDate: next,
            notificationDetails: details,
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            payload: _payload(schedule.id, anchor.label),
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
  Future<void> _cancelWhere(
    bool Function(String scheduleId) shouldCancel,
  ) async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final request in pending) {
      final payload = request.payload;
      if (payload == null || payload.isEmpty) continue;
      String? scheduleId;
      try {
        scheduleId =
            (jsonDecode(payload) as Map<String, dynamic>)['scheduleId']
                as String?;
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
    required Medicine medicine,
    required Duration delay,
  }) async {
    await init();
    final copy = await _copyFor(medicine);
    await _plugin.zonedSchedule(
      id: notificationIdFor(
        scheduleId,
        'snooze-${DateTime.now().millisecondsSinceEpoch}',
      ),
      title: copy.title,
      body: copy.body,
      scheduledDate: tz.TZDateTime.now(tz.local).add(delay),
      notificationDetails: _details(visibility: copy.visibility),
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
          visibility: careAlertLockScreenVisibility,
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
  Future<ReconcileReport> reconcile(AppDatabase db) async {
    await init();
    final active = await db.activeSchedulesOnce();
    // One sweep clears everything: alarms belonging to no active schedule
    // (orphans) and alarms belonging to one that's about to be re-armed
    // below. Doing both here is what lets the per-schedule calls skip their
    // own cancel pass — see [scheduleForScheduleWithMedicine].
    await _cancelWhere((_) => true);

    // Every schedule gets its own try/catch, because the sweep above has
    // already happened: without this, the first schedule that cannot be
    // armed leaves the device with *no* alarms rather than one fewer. That
    // is the failure this method exists to prevent, so it must not be able
    // to cause it.
    final failures = <String, Object>{};
    for (final sm in active) {
      try {
        await scheduleForScheduleWithMedicine(sm, skipCancel: true);
      } catch (error) {
        failures[sm.schedule.id] = error;
      }
    }
    return ReconcileReport(
      armed: active.length - failures.length,
      failures: failures,
    );
  }

  /// Re-arms from a short-lived database connection — for callers that do
  /// not already hold one, such as Settings when the lock-screen toggle
  /// changes. Matches the isolate pattern in push_handlers: open, use, close.
  Future<ReconcileReport> reconcileFromDisk() async {
    final db = AppDatabase();
    try {
      return await reconcile(db);
    } finally {
      await db.close();
    }
  }
}

/// What [NotificationService.reconcile] managed to arm.
///
/// Returned rather than logged so a caller can tell the user that a specific
/// reminder is not running. Nothing surfaces it yet; the value of returning
/// it now is that the information stops being thrown away.
class ReconcileReport {
  const ReconcileReport({required this.armed, required this.failures});

  /// Schedules whose alarms were armed without error.
  final int armed;

  /// Schedule id to the error that stopped it, for those that failed.
  final Map<String, Object> failures;

  bool get allArmed => failures.isEmpty;
}
