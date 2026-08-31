import 'package:dosely/features/reminders_home/reminder_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final loggedAt = DateTime(2026, 8, 26, 15, 0);

  test('active snooze uses the configured duration', () {
    final now = DateTime(2026, 8, 26, 15, 4, 59);

    expect(
      activeSnoozeUntil(
        action: 'snoozed',
        loggedAt: loggedAt,
        scheduleUpdatedAt: loggedAt,
        snoozeWindow: const Duration(minutes: 5),
        now: now,
      ),
      DateTime(2026, 8, 26, 15, 5),
    );
  });

  test('snooze status disappears at the configured expiry', () {
    expect(
      activeSnoozeUntil(
        action: 'snoozed',
        loggedAt: loggedAt,
        scheduleUpdatedAt: loggedAt,
        snoozeWindow: const Duration(minutes: 5),
        now: DateTime(2026, 8, 26, 15, 5),
      ),
      isNull,
    );
  });

  test('a snooze from before an edit does not mask the new reminder', () {
    expect(
      activeSnoozeUntil(
        action: 'snoozed',
        loggedAt: loggedAt,
        scheduleUpdatedAt: DateTime(2026, 8, 26, 15, 1),
        snoozeWindow: const Duration(minutes: 5),
        now: DateTime(2026, 8, 26, 15, 2),
      ),
      isNull,
    );
  });
}
