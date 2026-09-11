import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:medicyn/data/local/database.dart';
import 'package:medicyn/data/local/tables.dart';
import 'package:medicyn/features/reminders_home/reminder_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('Log now (as-needed medicines)', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<ScheduleWithMedicine> seed(FrequencyType frequency) async {
      await db.upsertMedicine(
        MedicinesCompanion.insert(id: 'm1', drugName: 'Ibuprofen'),
      );
      await db.upsertSchedule(
        SchedulesCompanion.insert(
          id: 's1',
          medicineId: 'm1',
          frequencyType: frequency.name,
          times: frequency == FrequencyType.asNeeded
              ? const <String>[]
              : const ['08:00'],
        ),
      );
      return ScheduleWithMedicine(
        (await db.scheduleById('s1'))!,
        (await db.medicineById('m1'))!,
      );
    }

    Widget harness(ScheduleWithMedicine item) => MaterialApp(
      home: Scaffold(
        body: ReminderCard(item: item, db: db, onTap: () {}, onDelete: () {}),
      ),
    );

    // ReminderCard mounts `_SnoozeStatus`, which arms its own poll Timer.
    // `testWidgets` does not unmount the previously-pumped tree on its own,
    // so without this, that Timer is still pending when the framework
    // checks for leaks at test end — see the identical note in
    // medicines_list_screen_test.dart, which hits the same widget.
    Future<void> disposeTree(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
    }

    testWidgets('does not appear on a scheduled (daily) medicine', (
      tester,
    ) async {
      final item = await seed(FrequencyType.daily);
      await tester.pumpWidget(harness(item));
      await tester.pump();

      expect(find.text('Log now'), findsNothing);
      await disposeTree(tester);
    });

    // Tapping the button itself is not exercised here: doing so runs
    // recordAsNeededDoseTaken -> recordDoseTaken -> _rescheduleAfterSettle,
    // which awaits NotificationService.scheduleForScheduleWithMedicine's
    // platform channel call (flutter_local_notifications) — the same call
    // prescription_review_screen_test.dart documents as never settling
    // inside a widget-test harness. That write path is instead covered
    // directly, without any widget involved, in
    // as_needed_logging_test.dart. What's under test here is just that the
    // card offers the action at all for an as-needed medicine.
    testWidgets('appears on an as-needed medicine', (tester) async {
      final item = await seed(FrequencyType.asNeeded);
      await tester.pumpWidget(harness(item));
      await tester.pump();

      expect(find.text('Log now'), findsOneWidget);
      await disposeTree(tester);
    });
  });
}
