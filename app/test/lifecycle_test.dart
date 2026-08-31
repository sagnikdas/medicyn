import 'package:dosely/data/local/database.dart';
import 'package:dosely/data/local/lifecycle.dart';
import 'package:dosely/data/local/tables.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> seed() async {
    await db.upsertMedicine(
      MedicinesCompanion.insert(id: 'medicine-1', drugName: 'Metformin'),
    );
    await db.upsertSchedule(
      SchedulesCompanion.insert(
        id: 'schedule-1',
        medicineId: 'medicine-1',
        frequencyType: FrequencyType.daily.name,
        times: const ['08:00'],
        status: const Value('active'),
      ),
    );
  }

  test(
    'pause and resume change lifecycle without deleting dose history',
    () async {
      await seed();
      await db.recordDoseAction(
        id: 'dose-1',
        scheduleId: 'schedule-1',
        scheduledAt: DateTime(2026, 8, 26, 8),
        action: DoseAction.taken,
      );

      await db.pauseSchedule(
        'schedule-1',
        until: DateTime(2026, 8, 30),
        by: 'user-1',
      );
      final paused = (await db.scheduleById('schedule-1'))!;
      expect(paused.status, ReminderStatus.paused.name);
      expect(paused.active, isFalse);
      expect(paused.pauseUntil, DateTime(2026, 8, 30));
      expect(await db.doseLogById('dose-1'), isNotNull);
      expect(reminderIsActive(paused, at: DateTime(2026, 8, 29)), isFalse);
      expect(
        reminderIsActive(paused, at: DateTime(2026, 8, 30)),
        isTrue,
        reason: 'an elapsed pause is eligible for automatic re-arm',
      );

      await db.resumeSchedule('schedule-1', by: 'user-1');
      final resumed = (await db.scheduleById('schedule-1'))!;
      expect(resumed.status, ReminderStatus.active.name);
      expect(resumed.active, isTrue);
      expect(resumed.pauseUntil, isNull);
      expect(resumed.updatedBy, 'user-1');
    },
  );

  test('completed reminders stay inactive and preserve history', () async {
    await seed();
    await db.completeSchedule('schedule-1');
    final schedule = (await db.scheduleById('schedule-1'))!;
    expect(reminderStatus(schedule), ReminderStatus.completed);
    expect(reminderIsActive(schedule), isFalse);
  });

  test('legacy inactive rows are interpreted as completed', () {
    final legacy = Schedule(
      id: 'schedule-1',
      medicineId: 'medicine-1',
      frequencyType: FrequencyType.daily.name,
      times: const ['08:00'],
      daysOfWeek: const [],
      active: false,
      createdAt: DateTime(2026, 8, 1),
      updatedAt: DateTime(2026, 8, 1),
      pendingSync: false,
      deleted: false,
    );
    expect(reminderStatus(legacy), ReminderStatus.completed);
  });
}
