import 'package:dosely/data/local/database.dart';
import 'package:dosely/data/local/tables.dart';
import 'package:dosely/features/reminders_home/day_occurrences.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Calendar status is what a family member reads at a glance. Both
/// directions of error are bad and they are bad differently: painting a
/// past dose as pending looks like it is still due, inventing missed
/// without a log tells someone their parent skipped a tablet they may
/// have taken. The cases below pin the boundaries.
void main() {
  // Friday, with reminders at 08:00 and 20:00.
  final now = DateTime(2026, 8, 21, 12, 0);
  final today = DateTime(2026, 8, 21);
  final yesterday = DateTime(2026, 8, 20);
  final tomorrow = DateTime(2026, 8, 22);
  const scheduleId = '0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0';
  const medicineId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  final longEstablished = DateTime(2026, 8, 1);

  Schedule schedule({
    String id = scheduleId,
    String medicineId = medicineId,
    FrequencyType frequency = FrequencyType.daily,
    List<String> times = const ['08:00', '20:00'],
    List<int> days = const [],
    int? intervalHours,
    bool active = true,
    bool deleted = false,
    DateTime? updatedAt,
  }) => Schedule(
    id: id,
    medicineId: medicineId,
    frequencyType: frequency.name,
    times: times,
    daysOfWeek: days,
    intervalHours: intervalHours,
    active: active,
    createdAt: DateTime(2026, 8, 1),
    updatedAt: updatedAt ?? longEstablished,
    updatedBy: null,
    pendingSync: false,
    deleted: deleted,
  );

  Medicine medicine({
    String id = medicineId,
    String name = 'Metformin',
    bool deleted = false,
  }) => Medicine(
    id: id,
    drugName: name,
    strength: '',
    form: '',
    doseAmount: '',
    notes: '',
    createdAt: DateTime(2026, 8, 1),
    updatedAt: DateTime(2026, 8, 1),
    pendingSync: false,
    deleted: deleted,
  );

  ScheduleWithMedicine item({Schedule? s, Medicine? m}) =>
      ScheduleWithMedicine(s ?? schedule(), m ?? medicine());

  DoseRecord record({
    String scheduleId = scheduleId,
    required DateTime scheduledAt,
    DateTime? loggedAt,
    DoseAction action = DoseAction.taken,
  }) => DoseRecord(
    scheduleId: scheduleId,
    scheduledAt: scheduledAt,
    loggedAt: loggedAt ?? scheduledAt,
    action: action,
  );

  List<DayOccurrence> onDay({
    required DateTime day,
    DateTime? at,
    List<ScheduleWithMedicine>? items,
    List<DoseRecord> logs = const [],
  }) => occurrencesOnDay(
    items: items ?? [item()],
    logs: logs,
    day: day,
    now: at ?? now,
  );

  test('today at noon: morning pending, evening upcoming', () {
    // 08:00 is four hours past and well outside grace; it must still be
    // pending, not notRecorded — the sweep may yet write missed.
    final occs = onDay(day: now);
    expect(occs, hasLength(2));
    expect(occs[0].scheduledAt, DateTime(2026, 8, 21, 8, 0));
    expect(occs[0].status, DayDoseStatus.pending);
    expect(occs[1].scheduledAt, DateTime(2026, 8, 21, 20, 0));
    expect(occs[1].status, DayDoseStatus.upcoming);
  });

  test('a taken log at 08:00 paints that slot taken', () {
    final occs = onDay(
      day: now,
      logs: [record(scheduledAt: DateTime(2026, 8, 21, 8, 0))],
    );
    expect(occs[0].status, DayDoseStatus.taken);
    expect(occs[1].status, DayDoseStatus.upcoming);
  });

  test('yesterday unanswered is notRecorded, not pending and not missed', () {
    // Silence beats a false alarm: nobody wrote missed, so the calendar
    // must not invent one, and a past day is never still "due".
    final occs = onDay(day: yesterday);
    expect(occs, hasLength(2));
    expect(occs.every((o) => o.status == DayDoseStatus.notRecorded), isTrue);
    expect(occs.any((o) => o.status == DayDoseStatus.pending), isFalse);
    expect(occs.any((o) => o.status == DayDoseStatus.missed), isFalse);
    expect(occs.any((o) => o.status == DayDoseStatus.upcoming), isFalse);
  });

  test('yesterday with a missed log is missed', () {
    final occs = onDay(
      day: yesterday,
      logs: [
        record(
          scheduledAt: DateTime(2026, 8, 20, 8, 0),
          action: DoseAction.missed,
        ),
      ],
    );
    expect(occs[0].status, DayDoseStatus.missed);
    expect(occs[1].status, DayDoseStatus.notRecorded);
  });

  test('a future date expected is pending', () {
    final occs = onDay(day: tomorrow);
    expect(occs, isNotEmpty);
    expect(occs.every((o) => o.status == DayDoseStatus.pending), isTrue);
  });

  test('a dose before the schedule was defined is omitted', () {
    // Saved at 10:00; the 08:00 alarm that morning was never armed.
    final occs = onDay(
      day: now,
      items: [item(s: schedule(updatedAt: DateTime(2026, 8, 21, 10, 0)))],
    );
    expect(occs, hasLength(1));
    expect(occs.single.scheduledAt, DateTime(2026, 8, 21, 20, 0));
    expect(occs.single.status, DayDoseStatus.upcoming);
  });

  test('inactive schedule with an old taken log shows that row only', () {
    // expectedDoses would return [] for inactive, which is why we walk
    // logs instead — but we must not invent a 20:00 pending beside it.
    final occs = onDay(
      day: now,
      items: [item(s: schedule(active: false))],
      logs: [record(scheduledAt: DateTime(2026, 8, 21, 8, 0))],
    );
    expect(occs, hasLength(1));
    expect(occs.single.status, DayDoseStatus.taken);
    expect(occs.single.scheduledAt, DateTime(2026, 8, 21, 8, 0));
  });

  test('a snooze is live for ten minutes and then falls through', () {
    final due = DateTime(2026, 8, 21, 8, 0);
    final live = onDay(
      day: now,
      logs: [
        record(
          scheduledAt: due,
          loggedAt: DateTime(2026, 8, 21, 11, 55),
          action: DoseAction.snoozed,
        ),
      ],
    );
    expect(live[0].status, DayDoseStatus.snoozed);

    final expired = onDay(
      day: now,
      logs: [
        record(
          scheduledAt: due,
          loggedAt: DateTime(2026, 8, 21, 11, 49),
          action: DoseAction.snoozed,
        ),
      ],
    );
    expect(expired[0].status, DayDoseStatus.pending);
  });

  test(
    'a snooze from before a schedule edit does not mask the edited dose',
    () {
      final due = DateTime(2026, 8, 21, 20, 0);
      final editedAt = DateTime(2026, 8, 21, 12, 0);
      final occs = onDay(
        day: now,
        at: DateTime(2026, 8, 21, 12, 30),
        items: [
          item(
            s: schedule(updatedAt: editedAt, times: const ['20:00']),
          ),
        ],
        logs: [
          record(
            scheduledAt: due,
            loggedAt: DateTime(2026, 8, 21, 11, 59),
            action: DoseAction.snoozed,
          ),
        ],
      );
      expect(occs.single.status, DayDoseStatus.upcoming);
    },
  );

  test('as-needed yields no occurrences', () {
    expect(
      onDay(
        day: now,
        items: [item(s: schedule(frequency: FrequencyType.asNeeded))],
      ),
      isEmpty,
    );
  });

  test('weekAdherence counts 2 taken of 3 due so far this week', () {
    // Defined Thursday morning so earlier weekdays are not armed. Friday
    // noon: Thu 08, Thu 20, Fri 08 are due; Fri 20 is upcoming; Saturday
    // is not "so far".
    final definedThursday = DateTime(2026, 8, 20, 7, 0);
    final items = [item(s: schedule(updatedAt: definedThursday))];
    final logs = [
      record(scheduledAt: DateTime(2026, 8, 20, 8, 0)),
      record(scheduledAt: DateTime(2026, 8, 20, 20, 0)),
    ];

    final result = weekAdherence(items: items, logs: logs, now: now);
    expect(result.taken, 2);
    expect(result.expected, 3);
  });

  test('weekDayAdherence matches weekAdherence totals', () {
    final definedThursday = DateTime(2026, 8, 20, 7, 0);
    final items = [item(s: schedule(updatedAt: definedThursday))];
    final logs = [
      record(scheduledAt: DateTime(2026, 8, 20, 8, 0)),
      record(scheduledAt: DateTime(2026, 8, 20, 20, 0)),
    ];
    final days = weekDayAdherence(items: items, logs: logs, now: now);
    expect(days, hasLength(7));
    expect(days[0].day, DateTime(2026, 8, 16)); // Sunday
    final taken = days.fold<int>(0, (n, d) => n + d.taken);
    final expected = days.fold<int>(0, (n, d) => n + d.expected);
    expect(taken, 2);
    expect(expected, 3);
  });

  test('nextActionableDose is the earliest pending or upcoming', () {
    final occs = onDay(day: now);
    final next = nextActionableDose(occs);
    expect(next?.scheduledAt, DateTime(2026, 8, 21, 8, 0));
    expect(next?.status, DayDoseStatus.pending);
  });

  test('attentionDoses lists today due and yesterday missed, not upcoming', () {
    final todayOccs = onDay(day: now);
    final yesterdayOccs = onDay(
      day: yesterday,
      logs: [
        record(
          scheduledAt: DateTime(2026, 8, 20, 8, 0),
          action: DoseAction.missed,
        ),
      ],
    );
    final attention = attentionDoses(
      today: todayOccs,
      yesterday: yesterdayOccs,
    );
    expect(attention.map((o) => o.scheduledAt).toList(), [
      DateTime(2026, 8, 21, 8, 0),
      DateTime(2026, 8, 20, 8, 0),
      DateTime(2026, 8, 20, 20, 0),
    ]);
    expect(attention.any((o) => o.status == DayDoseStatus.upcoming), isFalse);
    expect(doseCanSnooze(attention.first.status), isTrue);
    expect(doseStillRings(attention.first.status), isTrue);
    expect(doseCanSnooze(DayDoseStatus.missed), isFalse);
  });

  test('nextUpcomingDose skips the due morning dose', () {
    final next = nextUpcomingDose(onDay(day: now));
    expect(next?.scheduledAt, DateTime(2026, 8, 21, 20, 0));
    expect(next?.status, DayDoseStatus.upcoming);
  });

  test('dayPartOf splits morning afternoon evening', () {
    expect(dayPartOf(DateTime(2026, 8, 21, 8, 0)), DayPart.morning);
    expect(dayPartOf(DateTime(2026, 8, 21, 13, 0)), DayPart.afternoon);
    expect(dayPartOf(DateTime(2026, 8, 21, 20, 0)), DayPart.evening);
  });

  test('groupByDayPart puts 08:00 in morning and 20:00 in evening', () {
    final grouped = groupByDayPart(onDay(day: now));
    expect(grouped[DayPart.morning], hasLength(1));
    expect(grouped[DayPart.afternoon], isEmpty);
    expect(grouped[DayPart.evening], hasLength(1));
  });

  test('taken wins over a later snooze on the same slot', () {
    final due = DateTime(2026, 8, 21, 8, 0);
    final occs = onDay(
      day: now,
      logs: [
        record(scheduledAt: due, loggedAt: DateTime(2026, 8, 21, 8, 2)),
        record(
          scheduledAt: due,
          loggedAt: DateTime(2026, 8, 21, 8, 5),
          action: DoseAction.snoozed,
        ),
      ],
    );
    expect(occs[0].status, DayDoseStatus.taken);
  });

  test('cellMarksForRange ORs taken and pending on the same day', () {
    // Two morning slots, both already due at noon, one answered.
    final items = [
      item(s: schedule(times: const ['08:00', '09:00'])),
    ];
    final logs = [record(scheduledAt: DateTime(2026, 8, 21, 8, 0))];
    final marks = cellMarksForRange(
      items: items,
      logs: logs,
      rangeStart: today,
      rangeEnd: tomorrow,
      now: now,
    );

    expect(marks.keys, [today]);
    expect(marks[today]!.hasTaken, isTrue);
    expect(marks[today]!.hasPending, isTrue);
    expect(marks[today]!.hasUpcoming, isFalse);
    expect(marks[today]!.isEmpty, isFalse);
  });

  test('DoseRecord.tryFromLog skips an action the enum does not know', () {
    final known = DoseRecord.tryFromLog(
      DoseLog(
        id: 'log-1',
        scheduleId: scheduleId,
        scheduledAt: DateTime(2026, 8, 21, 8, 0),
        action: DoseAction.taken.name,
        loggedAt: DateTime(2026, 8, 21, 8, 1),
        source: 'notification',
        pendingSync: false,
      ),
    );
    expect(known, isNotNull);
    expect(known!.action, DoseAction.taken);

    final unknown = DoseRecord.tryFromLog(
      DoseLog(
        id: 'log-2',
        scheduleId: scheduleId,
        scheduledAt: DateTime(2026, 8, 21, 8, 0),
        action: 'skipped',
        loggedAt: DateTime(2026, 8, 21, 8, 1),
        source: 'notification',
        pendingSync: false,
      ),
    );
    expect(unknown, isNull);
  });

  group('AppDatabase queries the calendar needs', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await db.upsertMedicine(
        MedicinesCompanion.insert(id: medicineId, drugName: 'Metformin'),
      );
    });

    tearDown(() async => db.close());

    test(
      'schedulesWithMedicinesOnce includes inactive, excludes deleted',
      () async {
        await db.upsertSchedule(
          SchedulesCompanion.insert(
            id: scheduleId,
            medicineId: medicineId,
            frequencyType: FrequencyType.daily.name,
            times: const ['08:00'],
            updatedAt: Value(longEstablished),
          ),
        );
        await db.deactivateSchedule(scheduleId);

        final all = await db.schedulesWithMedicinesOnce();
        expect(all, hasLength(1));
        expect(all.single.schedule.active, isFalse);

        final activeOnly = await db.schedulesWithMedicinesOnce(
          activeOnly: true,
        );
        expect(activeOnly, isEmpty);
        expect(await db.activeSchedulesOnce(), isEmpty);
      },
    );

    test('doseLogsTouching matches on scheduledAt or loggedAt', () async {
      await db.upsertSchedule(
        SchedulesCompanion.insert(
          id: scheduleId,
          medicineId: medicineId,
          frequencyType: FrequencyType.daily.name,
          times: const ['08:00'],
          updatedAt: Value(longEstablished),
        ),
      );
      // Scheduled yesterday, answered today — the month view still needs it.
      await db.recordDoseAction(
        id: 'log-late',
        scheduleId: scheduleId,
        scheduledAt: DateTime(2026, 8, 20, 8, 0),
        action: DoseAction.taken,
        loggedAt: DateTime(2026, 8, 21, 9, 0),
      );
      // Scheduled today, logged tomorrow — still touching today via scheduledAt.
      await db.recordDoseAction(
        id: 'log-early-payload',
        scheduleId: scheduleId,
        scheduledAt: DateTime(2026, 8, 21, 8, 0),
        action: DoseAction.taken,
        loggedAt: DateTime(2026, 8, 22, 0, 10),
      );
      await db.recordDoseAction(
        id: 'log-other-month',
        scheduleId: scheduleId,
        scheduledAt: DateTime(2026, 7, 1, 8, 0),
        action: DoseAction.taken,
        loggedAt: DateTime(2026, 7, 1, 8, 4),
      );

      final touching = await db.doseLogsTouching(today, tomorrow);
      expect(touching.map((l) => l.id).toSet(), {
        'log-late',
        'log-early-payload',
      });
    });
  });
}
