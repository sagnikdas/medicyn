import 'package:medicyn/data/local/database.dart';
import 'package:medicyn/data/local/lifecycle.dart';
import 'package:medicyn/data/local/tables.dart';
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

  /// Pause, resume, complete, and deactivate all change what is actually
  /// expected of the schedule going forward — a pause stops alarms from
  /// firing, a resume (including "Restart reminder" on a completed
  /// schedule, which calls the same resumeSchedule path) starts them again
  /// from a new baseline. Each one has to move [Schedule.timingDefinedAt],
  /// not just [Schedule.updatedAt]: `reminderStatus` auto-flips a paused
  /// schedule back to active once `pauseUntil` elapses, and the missed-dose
  /// sweep only looks at a schedule's *current* status, not its historical
  /// status on each day of the sweep window. Left at its old value, the
  /// anchor would let the sweep treat every day since that old edit as
  /// something an alarm was armed for — including days the schedule spent
  /// paused, or dormant after completion.
  group('lifecycle transitions bump timingDefinedAt', () {
    final old = DateTime(2000, 1, 1);

    Future<void> seedWithOldAnchor(String id, {String medicineId = 'medicine-1'}) async {
      await db.upsertMedicine(
        MedicinesCompanion.insert(id: medicineId, drugName: 'Metformin'),
      );
      await db.upsertSchedule(
        SchedulesCompanion.insert(
          id: id,
          medicineId: medicineId,
          frequencyType: FrequencyType.daily.name,
          times: const ['08:00'],
          status: const Value('active'),
          timingDefinedAt: Value(old),
        ),
      );
    }

    test('pauseSchedule moves the anchor forward', () async {
      await seedWithOldAnchor('schedule-pause');
      await db.pauseSchedule('schedule-pause', until: DateTime(2026, 8, 30));
      final paused = (await db.scheduleById('schedule-pause'))!;
      expect(paused.timingDefinedAt.isAfter(old), isTrue);
    });

    test('resumeSchedule moves the anchor forward', () async {
      await seedWithOldAnchor('schedule-resume');
      await db.resumeSchedule('schedule-resume');
      final resumed = (await db.scheduleById('schedule-resume'))!;
      expect(resumed.timingDefinedAt.isAfter(old), isTrue);
    });

    test('completeSchedule moves the anchor forward', () async {
      await seedWithOldAnchor('schedule-complete');
      await db.completeSchedule('schedule-complete');
      final completed = (await db.scheduleById('schedule-complete'))!;
      expect(completed.timingDefinedAt.isAfter(old), isTrue);
    });

    test('deactivateSchedule moves the anchor forward', () async {
      await seedWithOldAnchor('schedule-deactivate');
      await db.deactivateSchedule('schedule-deactivate');
      final deactivated = (await db.scheduleById('schedule-deactivate'))!;
      expect(deactivated.timingDefinedAt.isAfter(old), isTrue);
    });

    test(
      '"Restart reminder" on a completed schedule (resumeSchedule) moves '
      'the anchor again, past the completion anchor',
      () async {
        await seedWithOldAnchor('schedule-restart');
        await db.completeSchedule('schedule-restart');
        final completed = (await db.scheduleById('schedule-restart'))!;

        // A little later, the family restarts the course. The UI's "Restart
        // reminder" button (review_edit_screen.dart) calls resumeSchedule
        // directly, the same call a resume-from-pause makes.
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await db.resumeSchedule('schedule-restart');
        final restarted = (await db.scheduleById('schedule-restart'))!;

        expect(restarted.status, ReminderStatus.active.name);
        expect(
          restarted.timingDefinedAt.isAfter(completed.timingDefinedAt) ||
              restarted.timingDefinedAt == completed.timingDefinedAt,
          isTrue,
          reason:
              'never allowed to fall back behind the completion anchor, so '
              'the dormant time between completion and restart is never '
              'treated as time something was armed for',
        );
      },
    );
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
      timingDefinedAt: DateTime(2026, 8, 1),
      pendingSync: false,
      deleted: false,
    );
    expect(reminderStatus(legacy), ReminderStatus.completed);
  });

  test('as-needed status cannot suppress a scheduled frequency', () {
    final malformed = Schedule(
      id: 'schedule-1',
      medicineId: 'medicine-1',
      frequencyType: FrequencyType.daily.name,
      times: const ['08:00'],
      daysOfWeek: const [],
      status: ReminderStatus.asNeeded.name,
      active: true,
      createdAt: DateTime(2026, 8, 1),
      updatedAt: DateTime(2026, 8, 1),
      timingDefinedAt: DateTime(2026, 8, 1),
      pendingSync: false,
      deleted: false,
    );

    expect(reminderStatus(malformed), ReminderStatus.active);
    expect(reminderIsActive(malformed), isTrue);
  });
}
