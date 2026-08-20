import 'package:dosely/data/local/database.dart';
import 'package:dosely/data/local/tables.dart';
import 'package:dosely/features/notification_engine/expected_doses.dart';
import 'package:dosely/features/notification_engine/missed_doses.dart';
import 'package:flutter_test/flutter_test.dart';

/// A wrong answer here marks a dose missed that never was, and tells a family
/// in another city that their parent skipped their medication. That is a
/// worse failure than saying nothing, so the cases below lean on the
/// boundaries.
void main() {
  Schedule schedule({
    required FrequencyType frequency,
    List<String> times = const ['08:00'],
    List<int> days = const [],
    int? intervalHours,
    bool active = true,
    DateTime? updatedAt,
  }) =>
      Schedule(
        id: '0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0',
        medicineId: 'med-1',
        frequencyType: frequency.name,
        times: times,
        daysOfWeek: days,
        intervalHours: intervalHours,
        active: active,
        createdAt: DateTime(2026, 8, 1),
        updatedAt: updatedAt ?? DateTime(2026, 8, 1),
        updatedBy: null,
        pendingSync: false,
        deleted: false,
      );

  group('a schedule stored before these fields were validated', () {
    test('reports nothing rather than aborting the whole sweep', () {
      // FrequencyType.values.byName threw here. Because expectedDoses runs
      // over every schedule in one pass, that took down missed-dose
      // detection for all of them - so a family would be told about none of
      // their relative's skipped doses, not just this one.
      final poisoned = Schedule(
        id: '0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0',
        medicineId: 'med-1',
        frequencyType: 'hourly',
        times: const ['08:00'],
        daysOfWeek: const [],
        intervalHours: null,
        active: true,
        createdAt: DateTime(2026, 8, 1),
        updatedAt: DateTime(2026, 8, 1),
        updatedBy: null,
        pendingSync: false,
        deleted: false,
      );

      expect(
        () => expectedDoses(poisoned, from: DateTime(2026, 8, 18), to: DateTime(2026, 8, 19)),
        returnsNormally,
      );
      expect(
        expectedDoses(poisoned, from: DateTime(2026, 8, 18), to: DateTime(2026, 8, 19)),
        isEmpty,
      );
    });
  });

  group('daily', () {
    test('finds one occurrence per day in the window', () {
      final doses = expectedDoses(
        schedule(frequency: FrequencyType.daily),
        from: DateTime(2026, 8, 16, 0, 0),
        to: DateTime(2026, 8, 19, 0, 0),
      );

      expect(doses, [
        DateTime(2026, 8, 16, 8, 0),
        DateTime(2026, 8, 17, 8, 0),
        DateTime(2026, 8, 18, 8, 0),
      ]);
    });

    test('returns several times a day in order', () {
      final doses = expectedDoses(
        schedule(frequency: FrequencyType.daily, times: ['21:00', '09:00']),
        from: DateTime(2026, 8, 18, 0, 0),
        to: DateTime(2026, 8, 19, 0, 0),
      );

      expect(doses, [
        DateTime(2026, 8, 18, 9, 0),
        DateTime(2026, 8, 18, 21, 0),
      ]);
    });

    test('excludes a dose falling exactly on the end of the window', () {
      // Half-open: a dose due at the cutoff has not happened yet, and
      // calling it missed the instant it comes due would be wrong.
      final doses = expectedDoses(
        schedule(frequency: FrequencyType.daily),
        from: DateTime(2026, 8, 18, 0, 0),
        to: DateTime(2026, 8, 18, 8, 0),
      );

      expect(doses, isEmpty);
    });

    test('includes a dose falling exactly on the start of the window', () {
      final doses = expectedDoses(
        schedule(frequency: FrequencyType.daily),
        from: DateTime(2026, 8, 18, 8, 0),
        to: DateTime(2026, 8, 18, 9, 0),
      );

      expect(doses, [DateTime(2026, 8, 18, 8, 0)]);
    });
  });

  group('specific days', () {
    test('only lands on the chosen weekdays', () {
      // 17 Aug 2026 is a Monday, so the week runs Mon 17 – Sun 23.
      // Stored days are 0=Sunday, so Monday=1 and Thursday=4.
      final doses = expectedDoses(
        schedule(frequency: FrequencyType.specificDays, days: [1, 4]),
        from: DateTime(2026, 8, 17, 0, 0),
        to: DateTime(2026, 8, 24, 0, 0),
      );

      expect(doses, [
        DateTime(2026, 8, 17, 8, 0), // Monday
        DateTime(2026, 8, 20, 8, 0), // Thursday
      ]);
    });

    test('handles Sunday, which the app stores as 0 and Dart as 7', () {
      // 23 Aug 2026 is a Sunday. Getting this mapping backwards would shift
      // every specific-days reminder by a day.
      final doses = expectedDoses(
        schedule(frequency: FrequencyType.specificDays, days: [0]),
        from: DateTime(2026, 8, 17, 0, 0),
        to: DateTime(2026, 8, 24, 0, 0),
      );

      expect(doses, [DateTime(2026, 8, 23, 8, 0)]);
    });

    test('returns nothing when no days are chosen', () {
      expect(
        expectedDoses(
          schedule(frequency: FrequencyType.specificDays, days: []),
          from: DateTime(2026, 8, 16),
          to: DateTime(2026, 8, 20),
        ),
        isEmpty,
      );
    });
  });

  group('every-x-hours shares the alarm lattice', () {
    test('reports occurrences from the definition-day origin', () {
      // Saved at 15:32 on the 8th with an 08:00 origin and a 5-hour step.
      // 08:00 and 13:00 that day are before the definition, so wasArmed
      // would drop them; expectedDoses still names them, and the sweep
      // applies wasArmed afterwards.
      expect(
        expectedDoses(
          schedule(
            frequency: FrequencyType.everyXHours,
            intervalHours: 5,
            times: const ['08:00'],
            updatedAt: DateTime(2026, 8, 8, 15, 32),
          ),
          from: DateTime(2026, 8, 8, 15, 32),
          to: DateTime(2026, 8, 9, 12, 0),
        ),
        [
          DateTime(2026, 8, 8, 18, 0),
          DateTime(2026, 8, 8, 23, 0),
          DateTime(2026, 8, 9, 4, 0),
          DateTime(2026, 8, 9, 9, 0),
        ],
      );
    });
  });

  group('frequencies that are deliberately not reported', () {

    test('as-needed yields nothing', () {
      expect(
        expectedDoses(
          schedule(frequency: FrequencyType.asNeeded),
          from: DateTime(2026, 8, 16),
          to: DateTime(2026, 8, 19),
        ),
        isEmpty,
      );
    });

    test('an inactive schedule yields nothing', () {
      expect(
        expectedDoses(
          schedule(frequency: FrequencyType.daily, active: false),
          from: DateTime(2026, 8, 16),
          to: DateTime(2026, 8, 19),
        ),
        isEmpty,
      );
    });
  });

  group('malformed input', () {
    test('skips an unparseable time without losing the others', () {
      final doses = expectedDoses(
        schedule(frequency: FrequencyType.daily, times: ['not-a-time', '08:00']),
        from: DateTime(2026, 8, 18, 0, 0),
        to: DateTime(2026, 8, 19, 0, 0),
      );

      expect(doses, [DateTime(2026, 8, 18, 8, 0)]);
    });

    test('rejects an out-of-range clock time', () {
      expect(
        expectedDoses(
          schedule(frequency: FrequencyType.daily, times: ['25:00']),
          from: DateTime(2026, 8, 18),
          to: DateTime(2026, 8, 19),
        ),
        isEmpty,
      );
    });

    test('returns nothing for an inverted window', () {
      expect(
        expectedDoses(
          schedule(frequency: FrequencyType.daily),
          from: DateTime(2026, 8, 19),
          to: DateTime(2026, 8, 16),
        ),
        isEmpty,
      );
    });
  });

  group('missedDoseId', () {
    const scheduleId = '0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0';

    test('is stable for the same schedule and time', () {
      final due = DateTime(2026, 8, 18, 8, 0);

      expect(missedDoseId(scheduleId, due), missedDoseId(scheduleId, due));
    });

    test('differs for different due times', () {
      expect(
        missedDoseId(scheduleId, DateTime(2026, 8, 18, 8, 0)),
        isNot(missedDoseId(scheduleId, DateTime(2026, 8, 18, 20, 0))),
      );
    });

    test('differs for different schedules at the same time', () {
      final due = DateTime(2026, 8, 18, 8, 0);

      expect(
        missedDoseId(scheduleId, due),
        isNot(missedDoseId('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee', due)),
      );
    });

    test('produces something Postgres will accept as a uuid', () {
      final id = missedDoseId(scheduleId, DateTime(2026, 8, 18, 8, 0));

      expect(
        RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
            .hasMatch(id),
        isTrue,
        reason: 'got $id',
      );
    });

    test('still returns a usable id when the schedule id is not a uuid', () {
      // Losing de-duplication is better than losing the dose.
      final id = missedDoseId('legacy-id', DateTime(2026, 8, 18, 8, 0));

      expect(id, isNotEmpty);
      expect(id.split('-').length, 5);
    });
  });
}
