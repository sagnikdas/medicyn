import 'package:dosely/core/theme.dart';
import 'package:dosely/data/local/database.dart';
import 'package:dosely/data/local/tables.dart';
import 'package:dosely/features/reminders_home/day_occurrences.dart';
import 'package:dosely/features/reminders_home/dose_attention_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 8, 21, 12, 0);
  const scheduleId = '0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0';
  const medicineId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';

  DayOccurrence occurrence({
    required DateTime scheduledAt,
    required DayDoseStatus status,
    String name = 'Metformin',
    String dose = '1 tablet',
  }) {
    return DayOccurrence(
      item: ScheduleWithMedicine(
        Schedule(
          id: scheduleId,
          medicineId: medicineId,
          frequencyType: FrequencyType.daily.name,
          times: const ['08:00'],
          daysOfWeek: const [],
          intervalHours: null,
          active: true,
          createdAt: DateTime(2026, 8, 1),
          updatedAt: DateTime(2026, 8, 1),
          updatedBy: null,
          pendingSync: false,
          deleted: false,
        ),
        Medicine(
          id: medicineId,
          drugName: name,
          strength: '500mg',
          form: '',
          doseAmount: dose,
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

  Future<void> pumpPanel(
    WidgetTester tester, {
    required List<DayOccurrence> occurrences,
    Future<void> Function(DayOccurrence o)? onTaken,
    Future<void> Function(DayOccurrence o)? onSnooze,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: DoselyTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: DoseAttentionPanel(
              occurrences: occurrences,
              now: now,
              onMarkTaken: onTaken ?? (_) async {},
              onSnooze: onSnooze ?? (_) async {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'due dose shows Taken and Snooze without hunting a notification',
    (tester) async {
      await pumpPanel(
        tester,
        occurrences: [
          occurrence(
            scheduledAt: DateTime(2026, 8, 21, 8, 0),
            status: DayDoseStatus.pending,
          ),
        ],
      );

      expect(find.text('Time for your medicine'), findsOneWidget);
      expect(
        find.textContaining('You do not have to find the alarm'),
        findsOneWidget,
      );
      expect(find.text('DUE NOW · 08:00'), findsOneWidget);
      expect(find.text('Metformin 500mg'), findsOneWidget);
      expect(find.text('Take 1 tablet'), findsOneWidget);
      expect(find.text('Mark as Taken'), findsOneWidget);
      expect(find.text('Snooze 10m'), findsOneWidget);
    },
  );

  testWidgets('a missed dose can still be marked taken, without snooze', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      occurrences: [
        occurrence(
          scheduledAt: DateTime(2026, 8, 20, 20, 0),
          status: DayDoseStatus.missed,
        ),
      ],
    );

    expect(find.text('YESTERDAY · 20:00'), findsOneWidget);
    expect(find.text('Mark as Taken'), findsOneWidget);
    expect(find.text('Snooze 10m'), findsNothing);
  });

  testWidgets('Taken on the panel records that dose', (tester) async {
    DayOccurrence? taken;
    await pumpPanel(
      tester,
      occurrences: [
        occurrence(
          scheduledAt: DateTime(2026, 8, 21, 8, 0),
          status: DayDoseStatus.pending,
        ),
      ],
      onTaken: (o) async => taken = o,
    );

    await tester.tap(find.text('Mark as Taken'));
    await tester.pump();
    expect(taken?.scheduledAt, DateTime(2026, 8, 21, 8, 0));
  });
}
