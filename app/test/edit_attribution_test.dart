import 'package:medicyn/features/care/care_service.dart';
import 'package:medicyn/features/care/edit_attribution.dart';
import 'package:medicyn/features/notification_engine/device_health.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('editAttributionLine', () {
    final created = DateTime(2026, 8, 18, 8);
    final tuesday = DateTime(2026, 8, 18, 10); // Tuesday
    const me = 'patient-1';
    const priya = 'caregiver-1';

    test('names the other person and the weekday', () {
      expect(
        editAttributionLine(
          updatedBy: priya,
          updatedAt: tuesday,
          createdAt: created,
          currentUserId: me,
          nameOf: (id) => id == priya ? 'Priya' : null,
          now: DateTime(2026, 8, 20, 12),
        ),
        'Changed by Priya, Tuesday',
      );
    });

    test('says you when this device wrote it', () {
      expect(
        editAttributionLine(
          updatedBy: me,
          updatedAt: tuesday,
          createdAt: created,
          currentUserId: me,
          now: DateTime(2026, 8, 20, 12),
        ),
        'Changed by you, Tuesday',
      );
    });

    test('says Added when create and update are the same moment', () {
      expect(
        editAttributionLine(
          updatedBy: priya,
          updatedAt: created,
          createdAt: created,
          currentUserId: me,
          nameOf: (_) => 'Priya',
          now: DateTime(2026, 8, 20, 12),
        ),
        'Added by Priya, Tuesday',
      );
    });

    test('is silent when nobody is stamped', () {
      expect(
        editAttributionLine(
          updatedBy: null,
          updatedAt: tuesday,
          createdAt: created,
          currentUserId: me,
        ),
        isNull,
      );
    });
  });

  group('describeLastSeen', () {
    test('says just now for a few seconds', () {
      final now = DateTime.utc(2026, 8, 20, 12);
      expect(describeLastSeen(now.subtract(const Duration(seconds: 10)), now: now), 'Just now');
    });

    test('counts minutes', () {
      final now = DateTime.utc(2026, 8, 20, 12);
      expect(describeLastSeen(now.subtract(const Duration(minutes: 7)), now: now), '7 minutes ago');
    });
  });

  group('CareProfile.remindersMayNotFire', () {
    test('is true when notifications are off', () {
      const profile = CareProfile(userId: 'p', notificationsAllowed: false);
      expect(profile.remindersMayNotFire, isTrue);
    });

    test('is true when nothing is armed', () {
      const profile = CareProfile(userId: 'p', armedAlarmCount: 0);
      expect(profile.remindersMayNotFire, isTrue);
    });

    test('is false when nothing has been reported yet', () {
      const profile = CareProfile(userId: 'p');
      expect(profile.remindersMayNotFire, isFalse);
    });
  });

  group('DeviceHealthSnapshot', () {
    test('flags a phone that cannot ring', () {
      final health = DeviceHealthSnapshot(
        notificationsAllowed: true,
        exactAlarmsAllowed: false,
        batteryExemption: true,
        armedAlarmCount: 3,
        checkedAt: DateTime.utc(2026, 8, 20),
      );
      expect(health.remindersMayNotFire, isTrue);
    });
  });

  group('editDelivered', () {
    final editCreatedAt = DateTime.utc(2026, 9, 10, 12);

    test('is pending when the recipient has never confirmed a sync', () {
      expect(
        editDelivered(
          editCreatedAt: editCreatedAt,
          recipientLastSyncedAt: null,
        ),
        isFalse,
      );
    });

    test('is pending when the last confirmed sync predates the edit', () {
      expect(
        editDelivered(
          editCreatedAt: editCreatedAt,
          recipientLastSyncedAt: editCreatedAt.subtract(
            const Duration(minutes: 1),
          ),
        ),
        isFalse,
      );
    });

    test('is delivered once a confirmed sync happened at the edit\'s moment',
        () {
      expect(
        editDelivered(
          editCreatedAt: editCreatedAt,
          recipientLastSyncedAt: editCreatedAt,
        ),
        isTrue,
      );
    });

    test('is delivered once a confirmed sync happened after the edit', () {
      expect(
        editDelivered(
          editCreatedAt: editCreatedAt,
          recipientLastSyncedAt: editCreatedAt.add(const Duration(hours: 1)),
        ),
        isTrue,
      );
    });
  });

  group('describeDeliveryStatus', () {
    test('names the two states honestly', () {
      expect(describeDeliveryStatus(true), 'Delivered as of last sync');
      expect(
        describeDeliveryStatus(false),
        'Pending — not yet synced everywhere',
      );
    });
  });
}
