import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicyn/core/theme.dart';
import 'package:medicyn/data/local/database.dart';
import 'package:medicyn/data/local/tables.dart';
import 'package:medicyn/features/reminders_home/day_dose_list.dart';
import 'package:medicyn/features/reminders_home/day_occurrences.dart';

void main() {
  testWidgets('day dose sliver lays out a dose row', (tester) async {
    final item = ScheduleWithMedicine(
      Schedule(
        id: 'schedule',
        medicineId: 'medicine',
        frequencyType: FrequencyType.daily.name,
        times: const ['08:00'],
        daysOfWeek: const [],
        intervalHours: null,
        status: ReminderStatus.active.name,
        startDate: null,
        endDate: null,
        pauseUntil: null,
        active: true,
        createdAt: DateTime(2026, 8, 1),
        updatedAt: DateTime(2026, 8, 1),
        updatedBy: null,
        pendingSync: false,
        deleted: false,
      ),
      Medicine(
        id: 'medicine',
        drugName: 'Metformin',
        strength: '500mg',
        form: 'tablet',
        doseAmount: '1 tablet',
        notes: '',
        createdAt: DateTime(2026, 8, 1),
        updatedAt: DateTime(2026, 8, 1),
        pendingSync: false,
        deleted: false,
      ),
    );
    final occurrence = DayOccurrence(
      item: item,
      scheduledAt: DateTime(2026, 8, 21, 8),
      status: DayDoseStatus.pending,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: MedicynTheme.light(),
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              ...dayDoseSlivers(
                day: DateTime(2026, 8, 21),
                now: DateTime(2026, 8, 21, 12),
                occurrences: [occurrence],
                onMarkTaken: (_) async {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Metformin'), findsOneWidget);
  });
}
