import 'package:dosely/data/local/database.dart';
import 'package:dosely/data/local/tables.dart';
import 'package:dosely/features/reminders_home/day_occurrences.dart';
import 'package:flutter_test/flutter_test.dart';

/// [DoseRecordIndex] narrows which logs a day is scored against, so the
/// risk it carries is a log that the old whole-history scan matched and
/// the bucketed lookup no longer reaches. These pin the three ways a log
/// can sit on a different calendar day from the slot it answers.
void main() {
  const scheduleId = 'sched-1';
  const medicineId = 'med-1';
  final defined = DateTime(2026, 1, 1);

  ScheduleWithMedicine item({
    List<String> times = const ['08:00'],
    bool active = true,
  }) =>
      ScheduleWithMedicine(
        Schedule(
          id: scheduleId,
          medicineId: medicineId,
          frequencyType: FrequencyType.daily.name,
          times: times,
          daysOfWeek: const [],
          intervalHours: null,
          active: active,
          createdAt: defined,
          updatedAt: defined,
          updatedBy: null,
          pendingSync: false,
          deleted: false,
        ),
        Medicine(
          id: medicineId,
          drugName: 'Metformin',
          strength: '',
          form: '',
          doseAmount: '',
          notes: '',
          createdAt: defined,
          updatedAt: defined,
          updatedBy: null,
          pendingSync: false,
          deleted: false,
          tabletsRemaining: null,
          tabletsPerDose: null,
        ),
      );

  DoseRecord record({
    required DateTime scheduledAt,
    required DateTime loggedAt,
    DoseAction action = DoseAction.taken,
  }) =>
      DoseRecord(
        scheduleId: scheduleId,
        scheduledAt: scheduledAt,
        loggedAt: loggedAt,
        action: action,
      );

  test('a midnight slot still sees a log stamped the previous day', () {
    // Reminder at 00:00; the log's scheduledAt is 30 seconds early, which
    // puts it on the day before but still inside the 60-second match.
    final day = DateTime(2026, 3, 10);
    final log = record(
      scheduledAt: DateTime(2026, 3, 9, 23, 59, 30),
      loggedAt: DateTime(2026, 3, 10, 0, 1),
    );
    final occs = occurrencesOnDay(
      items: [item(times: const ['00:00'])],
      logs: [log],
      day: day,
      now: DateTime(2026, 3, 10, 12),
    );
    expect(occs, hasLength(1));
    expect(occs.single.status, DayDoseStatus.taken);
  });

  test('a dose answered days after it was due still scores its own slot', () {
    // scheduledAt names 5 March; the person only answered on 10 March, so
    // the log is filed a working week away from the slot it belongs to.
    final log = record(
      scheduledAt: DateTime(2026, 3, 5, 8),
      loggedAt: DateTime(2026, 3, 10, 9),
    );
    final occs = occurrencesOnDay(
      items: [item()],
      logs: [log],
      day: DateTime(2026, 3, 5),
      now: DateTime(2026, 3, 11, 12),
    );
    expect(occs, hasLength(1));
    expect(occs.single.status, DayDoseStatus.taken);
  });

  test('a log landing inside the slot window wins even on another date', () {
    // No scheduledAt match: the payload named the wrong date entirely, and
    // only loggedAt falling in [due, nextDue) ties it to 10 March 08:00.
    final log = record(
      scheduledAt: DateTime(2026, 1, 1, 8),
      loggedAt: DateTime(2026, 3, 10, 8, 20),
    );
    final occs = occurrencesOnDay(
      items: [item()],
      logs: [log],
      day: DateTime(2026, 3, 10),
      now: DateTime(2026, 3, 10, 12),
    );
    expect(occs, hasLength(1));
    expect(occs.single.status, DayDoseStatus.taken);
  });

  test('a log filed under two days is not counted twice', () {
    // Inactive schedules paint straight from logs, which is where a
    // duplicate would surface as two occurrences for one dose.
    final log = record(
      scheduledAt: DateTime(2026, 3, 10, 23, 30),
      loggedAt: DateTime(2026, 3, 11, 0, 15),
    );
    final occs = occurrencesOnDay(
      items: [item(active: false)],
      logs: [log],
      day: DateTime(2026, 3, 10),
      now: DateTime(2026, 3, 12, 12),
    );
    expect(occs, hasLength(1));
  });

  test('a prebuilt index gives the same answer as passing raw logs', () {
    final logs = [
      for (var d = 1; d <= 20; d++)
        record(
          scheduledAt: DateTime(2026, 3, d, 8),
          loggedAt: DateTime(2026, 3, d, 8, 12),
        ),
    ];
    final index = DoseRecordIndex(logs);
    final now = DateTime(2026, 3, 21, 12);
    for (var d = 1; d <= 21; d++) {
      final day = DateTime(2026, 3, d);
      final fromLogs =
          occurrencesOnDay(items: [item()], logs: logs, day: day, now: now);
      final fromIndex =
          occurrencesOnDay(items: [item()], index: index, day: day, now: now);
      expect(fromIndex.map((o) => o.status).toList(),
          fromLogs.map((o) => o.status).toList(),
          reason: 'day $d');
      expect(fromIndex.map((o) => o.scheduledAt).toList(),
          fromLogs.map((o) => o.scheduledAt).toList(),
          reason: 'day $d');
    }
  });

  test('a schedule with no logs at all reads clean', () {
    final occs = occurrencesOnDay(
      items: [item()],
      logs: const [],
      day: DateTime(2026, 3, 10),
      now: DateTime(2026, 3, 12, 12),
    );
    expect(occs, hasLength(1));
    expect(occs.single.status, DayDoseStatus.notRecorded);
  });
}
