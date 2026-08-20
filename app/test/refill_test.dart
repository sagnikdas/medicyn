import 'package:dosely/data/local/database.dart';
import 'package:dosely/data/local/tables.dart';
import 'package:dosely/features/reminders_home/refill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
