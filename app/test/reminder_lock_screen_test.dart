import 'package:dosely/features/notification_engine/notification_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('reminderLockScreenCopy', () {
    test(
      'redacts name, strength and dose when the lock-screen setting is off',
      () {
        final copy = reminderLockScreenCopy(
          showMedicineOnLockScreen: false,
          drugName: 'Metformin',
          strength: '500mg',
          doseAmount: '1 tablet',
        );
        expect(copy.title, 'Medicine reminder');
        expect(copy.body, 'Time to take your dose');
        expect(copy.visibility, NotificationVisibility.private);
        expect(copy.title.toLowerCase(), isNot(contains('metformin')));
        expect(copy.body, isNot(contains('500mg')));
        expect(copy.body.toLowerCase(), isNot(contains('tablet')));
      },
    );

    test('keeps the named title and dose when the user opts in', () {
      final copy = reminderLockScreenCopy(
        showMedicineOnLockScreen: true,
        drugName: 'Metformin',
        strength: '500mg',
        doseAmount: '1 tablet',
      );
      expect(copy.title, 'Metformin 500mg');
      expect(copy.body, 'Take 1 tablet');
      expect(copy.visibility, NotificationVisibility.public);
    });

    test('omits an empty strength from the opted-in title', () {
      final copy = reminderLockScreenCopy(
        showMedicineOnLockScreen: true,
        drugName: 'Aspirin',
        strength: '',
        doseAmount: '',
      );
      expect(copy.title, 'Aspirin');
      expect(copy.body, 'Time for your dose');
    });
  });

  test('care alerts are private on the lock screen, with no named opt-in', () {
    expect(careAlertLockScreenVisibility, NotificationVisibility.private);
  });

  test(
    'isPatientReminderNotification never treats a care alert as an alarm',
    () {
      expect(
        isPatientReminderNotification(channelId: reminderChannelId),
        isTrue,
      );
      expect(
        isPatientReminderNotification(channelId: careAlertChannelId),
        isFalse,
      );
      expect(isPatientReminderNotification(channelId: null), isTrue);
    },
  );
}
