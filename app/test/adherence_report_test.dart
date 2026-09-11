import 'package:medicyn/data/export/adherence_report.dart';
import 'package:medicyn/data/local/database.dart';
import 'package:medicyn/data/local/tables.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A Tuesday, so the report window's math (Sunday-anchored weeks) is
  // actually exercised rather than accidentally landing on a week boundary.
  final now = DateTime(2026, 9, 8, 10);
  const longAgo = 90; // days before `now` schedules are "defined" at.
  final definedAt = now.subtract(const Duration(days: longAgo));

  ScheduleWithMedicine daily(
    String scheduleId,
    String medicineId, {
    String name = 'Metformin',
    List<String> times = const ['08:00'],
    String frequency = 'daily',
    String doseAmount = '1 tablet',
  }) {
    return ScheduleWithMedicine(
      Schedule(
        id: scheduleId,
        medicineId: medicineId,
        frequencyType: frequency,
        times: times,
        daysOfWeek: const [],
        intervalHours: null,
        active: true,
        createdAt: definedAt,
        updatedAt: definedAt,
        timingDefinedAt: definedAt,
        updatedBy: null,
        pendingSync: false,
        deleted: false,
      ),
      Medicine(
        id: medicineId,
        drugName: name,
        strength: '500mg',
        form: '',
        doseAmount: doseAmount,
        notes: '',
        createdAt: definedAt,
        updatedAt: definedAt,
        pendingSync: false,
        deleted: false,
      ),
    );
  }

  DoseLog log(
    String id,
    String scheduleId,
    DateTime scheduledAt, {
    DoseAction action = DoseAction.taken,
    DateTime? loggedAt,
  }) {
    return DoseLog(
      id: id,
      scheduleId: scheduleId,
      scheduledAt: scheduledAt,
      action: action.name,
      loggedAt: loggedAt ?? scheduledAt,
      source: 'notification',
      pendingSync: false,
    );
  }

  test(
    'report range is the 4 Sunday-Saturday weeks ending with now\'s week',
    () {
      final start = AdherenceReport.reportRangeStart(now);
      final endExclusive = AdherenceReport.reportRangeEndExclusive(now);

      // now (2026-09-08) is a Tuesday; its week starts Sunday 2026-09-06.
      expect(AdherenceReport.weekSunday(now), DateTime(2026, 9, 6));
      expect(start, DateTime(2026, 8, 16));
      expect(endExclusive, DateTime(2026, 9, 13));
      expect(endExclusive.difference(start).inDays, 28);
    },
  );

  test('generatedAt is the report\'s own `now`, not left unset', () {
    // Regression test: build() once passed a bare `generatedAt` identifier
    // that resolved to nothing declared in scope (a static-context bug the
    // analyzer caught as "instance member access from a static method").
    final report = AdherenceReport.build(
      items: const [],
      logs: const [],
      now: now,
    );
    expect(report.generatedAt, now);
  });

  test('counts taken vs. due doses across the window for a daily schedule', () {
    final item = daily('s1', 'm1');
    final logs = <DoseLog>[
      // Two days inside the window: one taken, one missed.
      log('l1', 's1', DateTime(2026, 8, 20, 8), action: DoseAction.taken),
      log('l2', 's1', DateTime(2026, 8, 21, 8), action: DoseAction.missed),
      // A day before the report window opens -- must not be counted.
      log('l0', 's1', DateTime(2026, 8, 1, 8), action: DoseAction.taken),
    ];
    final report = AdherenceReport.build(items: [item], logs: logs, now: now);

    expect(report.byMedicine, hasLength(1));
    expect(report.byMedicine.single.name, 'Metformin 500mg');
    expect(report.byMedicine.single.taken, 1);
    // Every day from 2026-08-16 up to and including "today" (2026-09-08)
    // is due for a daily 08:00 schedule that has run the whole window.
    final expectedDueDays =
        DateTime(2026, 9, 8).difference(DateTime(2026, 8, 16)).inDays + 1;
    expect(report.byMedicine.single.expected, expectedDueDays);
    expect(report.overall.taken, 1);
    expect(report.overall.expected, expectedDueDays);
  });

  test('as-needed medicines are shown but never scored', () {
    final item = daily('s1', 'm1', frequency: 'asNeeded', times: const []);
    final report = AdherenceReport.build(
      items: [item],
      logs: const [],
      now: now,
    );

    expect(report.currentSchedules, hasLength(1));
    expect(report.currentSchedules.single.scored, isFalse);
    expect(report.byMedicine, isEmpty);
    expect(report.overall, (taken: 0, expected: 0));
  });

  test('unanswered doses list truncates past unansweredPrintLimit', () {
    // Three times a day so the ~24 due days in the window comfortably clear
    // unansweredPrintLimit (40) without needing an unrealistic date range.
    final item = daily('s1', 'm1', times: const ['08:00', '14:00', '20:00']);
    final report = AdherenceReport.build(
      items: [item],
      logs: const [],
      now: now,
    );

    final totalUnanswered = report.unanswered.length + report.unansweredOmitted;
    expect(totalUnanswered, greaterThan(unansweredPrintLimit));
    expect(report.unanswered.length, unansweredPrintLimit);
    expect(report.unansweredOmitted, totalUnanswered - unansweredPrintLimit);
  });

  test('correction notes are scoped to the report window and named', () {
    final item = daily('s1', 'm1');
    final insideLog = log(
      'l1',
      's1',
      DateTime(2026, 8, 20, 8),
      action: DoseAction.missed,
    );
    final outsideLog = log(
      'l2',
      's1',
      DateTime(2026, 8, 1, 8),
      action: DoseAction.missed,
    );
    final contests = [
      DoseLogContest(
        doseLogId: 'l1',
        note: 'Actually took this one.',
        createdAt: now,
        updatedAt: now,
        pendingSync: false,
      ),
      DoseLogContest(
        doseLogId: 'l2',
        note: 'Outside the window, must not appear.',
        createdAt: now,
        updatedAt: now,
        pendingSync: false,
      ),
    ];
    final report = AdherenceReport.build(
      items: [item],
      logs: [insideLog, outsideLog],
      contests: contests,
      now: now,
    );

    expect(report.corrections, hasLength(1));
    expect(report.corrections.single.medicineName, 'Metformin 500mg');
    expect(report.corrections.single.note, 'Actually took this one.');
  });

  test('a login-email display name is not printed as the patient name', () {
    final report = AdherenceReport.build(
      items: const [],
      logs: const [],
      now: now,
      patientName: 'asha@example.com',
    );
    expect(report.patientName, isNull);
  });

  test('a real display name is kept', () {
    final report = AdherenceReport.build(
      items: const [],
      logs: const [],
      now: now,
      patientName: '  Asha Kapoor  ',
    );
    expect(report.patientName, 'Asha Kapoor');
  });
}
