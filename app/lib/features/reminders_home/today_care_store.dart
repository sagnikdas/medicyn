import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../data/local/database.dart';
import '../notification_engine/notification_ids.dart';
import '../notification_engine/notification_service.dart';
import 'today_care_events.dart';

enum TodayCareKind {
  test('Test', Icons.science_outlined, 'e.g. Blood test'),
  scan('Scan', Icons.document_scanner_outlined, 'e.g. MRI scan'),
  therapy('Therapy', Icons.self_improvement_outlined, 'e.g. Physiotherapy'),
  appointment(
    'Visit',
    Icons.medical_services_outlined,
    'e.g. Dental appointment',
  ),
  other('Other', Icons.event_outlined, 'e.g. Blood pressure check');

  const TodayCareKind(this.label, this.icon, this.hint);
  final String label;
  final IconData icon;
  final String hint;

  static TodayCareKind fromName(String value) =>
      values.firstWhere((kind) => kind.name == value, orElse: () => other);
}

class TodayCareStore {
  const TodayCareStore(this.db);
  final AppDatabase db;

  Stream<List<TodayCareReminder>> watch() =>
      (db.select(db.todayCareReminders)
            ..where((row) => row.deleted.equals(false))
            ..orderBy([(row) => OrderingTerm.asc(row.scheduledAt)]))
          .watch();

  Future<void> save(TodayCareReminder reminder) async {
    if (reminder.title.trim().isEmpty ||
        !TodayCareKind.values.any((kind) => kind.name == reminder.kind) ||
        (reminder.reminderMinutes != null && reminder.reminderMinutes! < 0)) {
      throw ArgumentError('Invalid care reminder');
    }
    await db.transaction(() async {
      final previous = await (db.select(
        db.todayCareReminders,
      )..where((row) => row.id.equals(reminder.id))).getSingleOrNull();
      await db
          .into(db.todayCareReminders)
          .insertOnConflictUpdate(
            reminder.copyWith(
              updatedAt: _nextVersion(previous?.updatedAt),
              pendingSync: true,
              deleted: false,
            ),
          );
    });
  }

  Future<void> remove(String id) => db.transaction(() async {
    final previous = await (db.select(
      db.todayCareReminders,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (previous == null) return;
    await (db.update(
      db.todayCareReminders,
    )..where((row) => row.id.equals(id))).write(
      TodayCareRemindersCompanion(
        deleted: const Value(true),
        pendingSync: const Value(true),
        updatedAt: Value(_nextVersion(previous.updatedAt)),
      ),
    );
  });

  static DateTime _nextVersion(DateTime? previous) {
    final now = DateTime.now().toUtc();
    return previous != null && !now.isAfter(previous)
        ? previous.add(const Duration(microseconds: 1))
        : now;
  }
}

/// Separate channel and payload namespace: medicine reconciliation and dose
/// actions must never cancel, log, or announce an appointment as a medicine.
class TodayCareNotifications {
  static const channelId = 'medicyn_today_care_v1';
  static const payloadKey = todayCarePayloadKey;
  final _plugin = FlutterLocalNotificationsPlugin();

  // Medicine IDs are strictly positive. Reserve negative IDs for this feature.
  static int idFor(String id) => -notificationIdFor(id, 'today-care');

  Future<void> cancel(String id) => _plugin.cancel(id: idFor(id));

  /// Returns false if Android notifications are unavailable. The agenda entry
  /// remains saved and the caller tells the user that the alert is not armed.
  Future<bool> schedule(
    TodayCareReminder reminder, {
    bool newlySaved = false,
  }) async {
    await NotificationService.instance.init();
    if (reminder.completed || reminder.reminderMinutes == null) {
      await cancel(reminder.id);
      return true;
    }
    final now = DateTime.now();
    if (!reminder.scheduledAt.isAfter(now)) return true;
    final requestedTime = reminder.scheduledAt.subtract(
      Duration(minutes: reminder.reminderMinutes!),
    );
    // Do not replay an advance alert that has already fired on app resume.
    // A newly saved event inside its advance window still gets an alert at
    // the event time; leave that pending fallback untouched on later resumes.
    if (!newlySaved && !requestedTime.isAfter(now)) return true;
    await cancel(reminder.id);
    if (!NotificationService.instance.timezoneReady) return false;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (await android?.areNotificationsEnabled() != true) return false;
    // If the advance notice has passed, still remind at the event time.
    final at = requestedTime.isAfter(now)
        ? requestedTime
        : reminder.scheduledAt;
    final exact = await android?.canScheduleExactNotifications() ?? false;
    await _plugin.zonedSchedule(
      id: idFor(reminder.id),
      title: 'Care reminder',
      body: 'You have scheduled care coming up. Open Today for details.',
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          'Scheduled care',
          channelDescription: 'Tests, scans, therapy and appointments.',
          importance: Importance.high,
          priority: Priority.high,
          visibility: NotificationVisibility.private,
        ),
      ),
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      payload: jsonEncode({payloadKey: reminder.id}),
    );
    return true;
  }

  Future<bool> reconcile(List<TodayCareReminder> reminders) async {
    await NotificationService.instance.init();
    final activeIds = {
      for (final reminder in reminders)
        if (!reminder.completed && reminder.reminderMinutes != null)
          reminder.id,
    };
    for (final pending in await _plugin.pendingNotificationRequests()) {
      try {
        final payload = jsonDecode(pending.payload ?? '') as Map;
        final id = payload[payloadKey];
        if (id is String && !activeIds.contains(id)) {
          await _plugin.cancel(id: pending.id);
        }
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
    }
    var allArmed = true;
    for (final reminder in reminders) {
      try {
        if (!await schedule(reminder)) allArmed = false;
      } catch (_) {
        allArmed = false;
      }
    }
    return allArmed;
  }
}
