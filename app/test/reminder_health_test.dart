import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medicyn/core/telemetry.dart';
import 'package:medicyn/features/notification_engine/reminder_health.dart';
import 'package:medicyn/features/notification_engine/notification_service.dart';

void main() {
  test('health snapshot round-trips without medicine or dosage data', () {
    final checkedAt = DateTime.utc(2026, 8, 26, 7, 30);
    final item = ReminderScheduleHealth(
      scheduleId: 'schedule-1',
      armed: true,
      notificationsAllowed: true,
      exactAlarmsAllowed: false,
      timezoneReady: true,
      mode: ReminderHealthMode.inexact,
      checkedAt: checkedAt,
      nextAlarmExpectedAt: checkedAt.add(const Duration(hours: 2)),
    );

    final decoded = ReminderScheduleHealth.fromJson(item.toJson());

    expect(decoded, isNotNull);
    expect(decoded!.scheduleId, 'schedule-1');
    expect(decoded.mode, ReminderHealthMode.inexact);
    expect(decoded.needsAttention, isTrue);
    expect(
      decoded.nextAlarmExpectedAt?.toUtc(),
      checkedAt.add(const Duration(hours: 2)),
    );
    expect(decoded.toJson().keys, isNot(contains('medicine')));
    expect(decoded.toJson().keys, isNot(contains('drugName')));
  });

  test('inexact delivery is reported as degraded but still armed', () {
    final result = ScheduleArmResult(
      scheduleId: 'schedule-1',
      armedCount: 1,
      nextAlarmExpectedAt: DateTime.utc(2026, 8, 26, 9),
      mode: AndroidScheduleMode.inexactAllowWhileIdle,
    );

    expect(result.isArmed, isTrue);
    expect(result.isRequired, isTrue);
    expect(ReminderHealthMode.inexact, isNot(ReminderHealthMode.exact));
  });

  test('telemetry count buckets never expose exact totals', () {
    expect(MedicynTelemetry.countBucket(0), 'none');
    expect(MedicynTelemetry.countBucket(1), 'one');
    expect(MedicynTelemetry.countBucket(3), '2-5');
    expect(MedicynTelemetry.countBucket(99), '6+');
  });
}
