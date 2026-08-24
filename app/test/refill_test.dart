import 'package:dosely/data/local/database.dart';
import 'package:dosely/data/local/tables.dart';
import 'package:dosely/features/reminders_home/refill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Medicine medicine({int? tabletsRemaining, int? tabletsPerDose}) => Medicine(
        id: 'm1',
        drugName: 'Metformin',
        strength: '',
        form: '',
        doseAmount: '',
        tabletsRemaining: tabletsRemaining,
        tabletsPerDose: tabletsPerDose,
        notes: '',
        createdAt: DateTime(2026, 8, 1),
        updatedAt: DateTime(2026, 8, 1),
        updatedBy: null,
        pendingSync: false,
        deleted: false,
      );

  Schedule daily({List<String> times = const ['08:00', '20:00']}) => Schedule(
        id: 's1',
        medicineId: 'm1',
        frequencyType: FrequencyType.daily.name,
        times: times,
        daysOfWeek: const [],
        intervalHours: null,
        active: true,
        createdAt: DateTime(2026, 8, 1),
        updatedAt: DateTime(2026, 8, 1),
        updatedBy: null,
        pendingSync: false,
        deleted: false,
      );

  test('a twice-daily tablet lasts five days at ten remaining', () {
    expect(
      refillDaysLeft(
        tabletsRemaining: 10,
        tabletsPerDose: 1,
        schedules: [daily()],
      ),
      5,
    );
    expect(
      refillIsLow(refillDaysLeft(
        tabletsRemaining: 10,
        tabletsPerDose: 1,
        schedules: [daily()],
      )),
      isTrue,
    );
  });

  test('twelve remaining is the first day over the five-day warning', () {
    expect(
      refillDaysLeft(
        tabletsRemaining: 11,
        tabletsPerDose: 1,
        schedules: [daily()],
      ),
      5,
    );
    expect(
      refillIsLow(refillDaysLeft(
        tabletsRemaining: 12,
        tabletsPerDose: 1,
        schedules: [daily()],
      )),
      isFalse,
    );
  });

  test('null remaining means tracking is off', () {
    expect(
      refillDaysLeft(
        tabletsRemaining: null,
        tabletsPerDose: 1,
        schedules: [daily()],
      ),
      isNull,
    );
    expect(refillWarningLine(null), isNull);
  });

  test('an empty bottle is zero days, not a guess', () {
    expect(
      refillDaysLeft(
        tabletsRemaining: 0,
        tabletsPerDose: 1,
        schedules: [daily()],
      ),
      0,
    );
    expect(refillWarningLine(0), 'No tablets left');
  });

  test('as-needed has no daily rate, so there is nothing to warn about', () {
    final asNeeded = daily() /* frequency overwritten below */;
    final schedule = Schedule(
      id: asNeeded.id,
      medicineId: asNeeded.medicineId,
      frequencyType: FrequencyType.asNeeded.name,
      times: asNeeded.times,
      daysOfWeek: asNeeded.daysOfWeek,
      intervalHours: asNeeded.intervalHours,
      active: true,
      createdAt: asNeeded.createdAt,
      updatedAt: asNeeded.updatedAt,
      updatedBy: null,
      pendingSync: false,
      deleted: false,
    );
    expect(
      refillDaysLeft(
        tabletsRemaining: 10,
        tabletsPerDose: 1,
        schedules: [schedule],
      ),
      isNull,
    );
  });

  group('derivedTabletsRemaining', () {
    test('subtracts what has been taken since the baseline was set', () {
      expect(
        derivedTabletsRemaining(medicine(tabletsRemaining: 30, tabletsPerDose: 1), 2),
        28,
      );
    });

    test('multiplies by tablets per dose', () {
      expect(
        derivedTabletsRemaining(medicine(tabletsRemaining: 30, tabletsPerDose: 2), 3),
        24,
      );
    });

    test('floors at zero rather than going negative', () {
      expect(
        derivedTabletsRemaining(medicine(tabletsRemaining: 3, tabletsPerDose: 2), 5),
        0,
      );
    });

    test('null baseline means the bottle is not tracked', () {
      expect(derivedTabletsRemaining(medicine(tabletsPerDose: 1), 2), isNull);
    });

    test('nothing taken yet leaves the baseline untouched', () {
      expect(
        derivedTabletsRemaining(medicine(tabletsRemaining: 30, tabletsPerDose: 1), 0),
        30,
      );
    });
  });

  group('anyRefillLow', () {
    ScheduleWithMedicine item({int? tabletsRemaining}) => ScheduleWithMedicine(
          daily(),
          medicine(tabletsRemaining: tabletsRemaining, tabletsPerDose: 1),
        );

    test('a dose taken since the baseline can push a bottle into the warning', () {
      // Baseline of 12 (over the 5-day warning at 2/day) minus 8 taken lands
      // on 4 remaining — two days, which is low. Passing the raw baseline
      // with nothing taken must not have warned yet.
      expect(anyRefillLow([item(tabletsRemaining: 12)], const {}), isFalse);
      expect(anyRefillLow([item(tabletsRemaining: 12)], const {'m1': 8}), isTrue);
    });

    test('a medicine missing from the map is treated as nothing taken', () {
      expect(anyRefillLow([item(tabletsRemaining: 12)], const {'other': 8}), isFalse);
    });
  });
}
