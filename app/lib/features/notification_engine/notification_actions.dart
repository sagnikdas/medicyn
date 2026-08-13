import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../core/ids.dart';
import '../../data/local/database.dart';
import '../../data/local/tables.dart';
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

/// Shared by both the foreground and background entry points. Opens its own
/// short-lived database connection rather than relying on an app-wide
/// singleton, since a background isolate has none of the app's state.
void handleNotificationResponse(NotificationResponse response) async {
  final actionId = response.actionId;
  if (actionId != actionTaken && actionId != actionSnooze) {
    return; // Plain notification tap (no action button) — nothing to record.
  }

  final payloadRaw = response.payload;
  if (payloadRaw == null || payloadRaw.isEmpty) return;
  final payload = jsonDecode(payloadRaw) as Map<String, dynamic>;
  final scheduleId = payload['scheduleId'] as String?;
  if (scheduleId == null) return;

  final db = AppDatabase();
  try {
    if (actionId == actionTaken) {
      await db.recordDoseAction(
        id: newUuid(),
        scheduleId: scheduleId,
        scheduledAt: DateTime.now(),
        action: DoseAction.taken,
      );
      return;
    }

    // Snooze: log it, then arm a one-off reminder 10 minutes out.
    await db.recordDoseAction(
      id: newUuid(),
      scheduleId: scheduleId,
      scheduledAt: DateTime.now(),
      action: DoseAction.snoozed,
    );
    final schedule = await db.scheduleById(scheduleId);
    if (schedule == null) return;
    final medicine = await db.medicineById(schedule.medicineId);
    if (medicine == null) return;

    await NotificationService.instance.scheduleSnooze(
      scheduleId: scheduleId,
      title: medicine.strength.isEmpty ? medicine.drugName : '${medicine.drugName} ${medicine.strength}',
      body: medicine.doseAmount.isEmpty ? 'Time for your dose' : 'Take ${medicine.doseAmount}',
      delay: const Duration(minutes: 10),
    );
  } finally {
    await db.close();
  }
}
