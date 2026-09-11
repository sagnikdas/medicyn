import 'package:medicyn/core/theme.dart';
import 'package:medicyn/data/local/database.dart';
import 'package:medicyn/data/local/tables.dart';
import 'package:medicyn/features/reminders_home/day_occurrences.dart';
import 'package:medicyn/features/reminders_home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const scheduleId = '0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0';
  const medicineId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';

  DayOccurrence occurrence({
    required DateTime scheduledAt,
    required DayDoseStatus status,
    String scheduleIdOverride = scheduleId,
  }) {
    return DayOccurrence(
      item: ScheduleWithMedicine(
        Schedule(
          id: scheduleIdOverride,
          medicineId: medicineId,
          frequencyType: FrequencyType.daily.name,
          times: const ['08:00'],
          daysOfWeek: const [],
          intervalHours: null,
          active: true,
          createdAt: DateTime(2026, 8, 1),
          updatedAt: DateTime(2026, 8, 1),
          timingDefinedAt: DateTime(2026, 8, 1),
          updatedBy: null,
          pendingSync: false,
          deleted: false,
        ),
        Medicine(
          id: medicineId,
          drugName: 'Metformin',
          strength: '500mg',
          form: '',
          doseAmount: '1 tablet',
          notes: '',
          createdAt: DateTime(2026, 8, 1),
          updatedAt: DateTime(2026, 8, 1),
          pendingSync: false,
          deleted: false,
        ),
      ),
      scheduledAt: scheduledAt,
      status: status,
    );
  }

  group('missedDoseNudgeOccurrences', () {
    test('picks out only today\'s own missed doses', () {
      final missed = occurrence(
        scheduledAt: DateTime(2026, 8, 21, 8, 0),
        status: DayDoseStatus.missed,
      );
      final result = missedDoseNudgeOccurrences(
        today: [
          missed,
          occurrence(
            scheduledAt: DateTime(2026, 8, 21, 20, 0),
            status: DayDoseStatus.pending,
          ),
          occurrence(
            scheduledAt: DateTime(2026, 8, 21, 12, 0),
            status: DayDoseStatus.taken,
          ),
        ],
        dismissedKeys: {},
      );

      expect(result, [missed]);
    });

    test('a dismissed occurrence is excluded even though it is still missed', () {
      final missed = occurrence(
        scheduledAt: DateTime(2026, 8, 21, 8, 0),
        status: DayDoseStatus.missed,
      );
      final result = missedDoseNudgeOccurrences(
        today: [missed],
        dismissedKeys: {dayOccurrenceKey(missed)},
      );

      expect(result, isEmpty);
    });

    test('a different missed occurrence is unaffected by another one\'s '
        'dismissal', () {
      final dismissed = occurrence(
        scheduledAt: DateTime(2026, 8, 21, 8, 0),
        status: DayDoseStatus.missed,
      );
      final stillPending = occurrence(
        scheduledAt: DateTime(2026, 8, 21, 20, 0),
        status: DayDoseStatus.missed,
      );
      final result = missedDoseNudgeOccurrences(
        today: [dismissed, stillPending],
        dismissedKeys: {dayOccurrenceKey(dismissed)},
      );

      expect(result, [stillPending]);
    });
  });

  group('MissedDoseNudgeCard', () {
    Future<void> pumpCard(
      WidgetTester tester, {
      required int count,
      VoidCallback? onDismiss,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          theme: MedicynTheme.light(),
          home: Scaffold(
            body: MissedDoseNudgeCard(
              count: count,
              onDismiss: onDismiss ?? () {},
            ),
          ),
        ),
      );
    }

    testWidgets('reads as a supportive nudge, not a report to a caregiver', (
      tester,
    ) async {
      await pumpCard(tester, count: 1);

      expect(
        find.text('Looks like you missed a dose earlier'),
        findsOneWidget,
      );
      expect(
        find.textContaining('No worries'),
        findsOneWidget,
      );
      expect(find.textContaining('caregiver'), findsNothing);
      expect(find.textContaining('told'), findsNothing);
    });

    testWidgets('pluralizes the count for more than one missed dose', (
      tester,
    ) async {
      await pumpCard(tester, count: 3);

      expect(
        find.text('Looks like you missed 3 doses earlier'),
        findsOneWidget,
      );
    });

    testWidgets('the close button dismisses it', (tester) async {
      var dismissed = false;
      await pumpCard(tester, count: 1, onDismiss: () => dismissed = true);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      expect(dismissed, isTrue);
    });
  });
}
