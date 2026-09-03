import 'package:medicyn/features/notification_engine/notification_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  NotificationResponse response({int id = 7, String? payload}) {
    return NotificationResponse(
      id: id,
      notificationResponseType: NotificationResponseType.selectedNotification,
      payload: payload ?? '{"scheduleId":"s1","timeLabel":"18:00"}',
    );
  }

  test('same launch is ignored for the rest of the day', () {
    final now = DateTime(2026, 8, 21, 17, 55);
    final fingerprint = notificationLaunchFingerprint(response(), now);
    expect(
      shouldOpenFromLaunchDetails(
        fingerprint: fingerprint,
        alreadyHandled: fingerprint,
      ),
      isFalse,
    );
  });

  test('a different notification still opens', () {
    final now = DateTime(2026, 8, 21, 17, 55);
    final first = notificationLaunchFingerprint(response(id: 1), now);
    final second = notificationLaunchFingerprint(response(id: 2), now);
    expect(
      shouldOpenFromLaunchDetails(fingerprint: second, alreadyHandled: first),
      isTrue,
    );
  });

  test('the same daily slot can open again the next day', () {
    final tap = response();
    final today = notificationLaunchFingerprint(tap, DateTime(2026, 8, 21));
    final tomorrow = notificationLaunchFingerprint(tap, DateTime(2026, 8, 22));
    expect(today, isNot(tomorrow));
    expect(
      shouldOpenFromLaunchDetails(fingerprint: tomorrow, alreadyHandled: today),
      isTrue,
    );
  });
}
