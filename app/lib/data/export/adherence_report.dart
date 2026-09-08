import '../../core/app_settings.dart';
import '../../data/local/database.dart';
import '../../data/local/lifecycle.dart';
import '../../data/local/tables.dart';
import '../../features/notification_engine/schedule_validation.dart';
import '../../features/reminders_home/day_dose_style.dart';
import '../../features/reminders_home/day_occurrences.dart';
import '../../features/reminders_home/reminder_copy.dart';

/// Four Sunday–Saturday weeks ending with the week that contains [now].
const adherenceReportWeeks = 4;

/// How many unanswered rows the PDF prints before collapsing the rest.
const unansweredPrintLimit = 40;

/// A clinician-facing summary of what this device logged. Scoring is the
/// same lattice Home and Insights already use: as-needed medicines never
/// enter the denominator, and upcoming / future slots are not counted.
class AdherenceReport {
  const AdherenceReport({
    required this.generatedAt,
    required this.rangeStart,
    required this.rangeEndExclusive,
    required this.patientName,
    required this.overall,
    required this.byWeek,
    required this.byMedicine,
    required this.currentSchedules,
    required this.unanswered,
    required this.unansweredOmitted,
    required this.corrections,
  });

  final DateTime generatedAt;
  final DateTime rangeStart;
  final DateTime rangeEndExclusive;
  final String? patientName;
  final ({int taken, int expected}) overall;
  final List<AdherenceWeekRow> byWeek;
  final List<AdherenceMedicineRow> byMedicine;
  final List<AdherenceScheduleRow> currentSchedules;
  final List<AdherenceUnansweredRow> unanswered;
  final int unansweredOmitted;
  final List<AdherenceCorrectionRow> corrections;

  DateTime get rangeEndInclusive => addCalendarDays(rangeEndExclusive, -1);

  static DateTime weekSunday(DateTime now) {
    final today = calendarDay(now);
    final storedWeekday = now.weekday == DateTime.sunday ? 0 : now.weekday;
    return addCalendarDays(today, -storedWeekday);
  }

  static DateTime reportRangeStart(DateTime now) =>
      addCalendarDays(weekSunday(now), -7 * (adherenceReportWeeks - 1));

  static DateTime reportRangeEndExclusive(DateTime now) =>
      addCalendarDays(weekSunday(now), 7);

  static Future<AdherenceReport> fromDatabase(
    AppDatabase db, {
    DateTime? now,
    String? patientName,
    Duration? snoozeWindow,
  }) async {
    final generatedAt = now ?? DateTime.now();
    final items = await db.schedulesWithMedicinesOnce();
    final logs = await db.select(db.doseLogs).get();
    final contests = await db.select(db.doseLogContests).get();
    return build(
      items: items,
      logs: logs,
      contests: contests,
      now: generatedAt,
      patientName: patientName,
      snoozeWindow:
          snoozeWindow ?? Duration(minutes: AppSettings.instance.snoozeMinutes),
    );
  }

  static AdherenceReport build({
    required List<ScheduleWithMedicine> items,
    required List<DoseLog> logs,
    List<DoseLogContest> contests = const [],
    required DateTime now,
    String? patientName,
    Duration snoozeWindow = const Duration(minutes: 10),
  }) {
    final records = <DoseRecord>[
      for (final log in logs) ?DoseRecord.tryFromLog(log),
    ];
    final index = DoseRecordIndex(records);
    final start = reportRangeStart(now);
    final endExclusive = reportRangeEndExclusive(now);
    final today = calendarDay(now);

    final overall = rangeAdherence(
      items: items,
      index: index,
      now: now,
      rangeStart: start,
      rangeEndExclusive: endExclusive,
      snoozeWindow: snoozeWindow,
    );

    final byWeek = <AdherenceWeekRow>[];
    for (var i = 0; i < adherenceReportWeeks; i++) {
      final weekStart = addCalendarDays(start, i * 7);
      final weekEnd = addCalendarDays(weekStart, 7);
      final counts = rangeAdherence(
        items: items,
        index: index,
        now: now,
        rangeStart: weekStart,
        rangeEndExclusive: weekEnd,
        snoozeWindow: snoozeWindow,
      );
      byWeek.add(AdherenceWeekRow(weekStart: weekStart, counts: counts));
    }

    final takenByMedicine = <String, int>{};
    final expectedByMedicine = <String, int>{};
    final nameByMedicine = <String, String>{};
    final unanswered = <AdherenceUnansweredRow>[];

    var day = start;
    while (day.isBefore(endExclusive)) {
      final occs = occurrencesOnDay(
        items: items,
        index: index,
        day: day,
        now: now,
        snoozeWindow: snoozeWindow,
      );
      for (final o in occs) {
        final medicineId = o.item.medicine.id;
        nameByMedicine[medicineId] = medicineTitle(o.item.medicine);
        if (o.status == DayDoseStatus.taken) {
          takenByMedicine[medicineId] = (takenByMedicine[medicineId] ?? 0) + 1;
        }
        final countsTowardExpected =
            o.status != DayDoseStatus.upcoming &&
            !calendarDay(o.scheduledAt).isAfter(today);
        if (countsTowardExpected) {
          expectedByMedicine[medicineId] =
              (expectedByMedicine[medicineId] ?? 0) + 1;
        }
        if (o.status == DayDoseStatus.missed ||
            o.status == DayDoseStatus.notRecorded) {
          unanswered.add(
            AdherenceUnansweredRow(
              scheduledAt: o.scheduledAt,
              medicineName: medicineTitle(o.item.medicine),
              statusLabel: DayDoseStyle.label(o.status),
            ),
          );
        }
      }
      day = addCalendarDays(day, 1);
    }

    final byMedicine = [
      for (final id in expectedByMedicine.keys)
        AdherenceMedicineRow(
          name: nameByMedicine[id] ?? id,
          taken: takenByMedicine[id] ?? 0,
          expected: expectedByMedicine[id] ?? 0,
        ),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    unanswered.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    final omitted = unanswered.length > unansweredPrintLimit
        ? unanswered.length - unansweredPrintLimit
        : 0;
    final printed = omitted == 0
        ? unanswered
        : unanswered.sublist(0, unansweredPrintLimit);

    final logsById = {for (final log in logs) log.id: log};
    final itemBySchedule = {for (final item in items) item.schedule.id: item};
    final corrections = <AdherenceCorrectionRow>[];
    for (final contest in contests) {
      final log = logsById[contest.doseLogId];
      if (log == null) continue;
      final scheduled = calendarDay(log.scheduledAt);
      if (scheduled.isBefore(start) || !scheduled.isBefore(endExclusive)) {
        continue;
      }
      final item = itemBySchedule[log.scheduleId];
      corrections.add(
        AdherenceCorrectionRow(
          scheduledAt: log.scheduledAt,
          medicineName: item == null
              ? 'Unknown medicine'
              : medicineTitle(item.medicine),
          note: contest.note,
        ),
      );
    }
    corrections.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

    final currentSchedules = [
      for (final item in items)
        AdherenceScheduleRow(
          title: medicineTitle(item.medicine),
          dose: item.medicine.doseAmount.trim(),
          schedule: describeSchedule(item.schedule),
          status: _statusLabel(item.schedule, now),
          scored:
              frequencyTypeFromName(item.schedule.frequencyType) !=
              FrequencyType.asNeeded,
        ),
    ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    return AdherenceReport(
      generatedAt: now,
      rangeStart: start,
      rangeEndExclusive: endExclusive,
      patientName: _printableName(patientName),
      overall: overall,
      byWeek: byWeek,
      byMedicine: byMedicine,
      currentSchedules: currentSchedules,
      unanswered: printed,
      unansweredOmitted: omitted,
      corrections: corrections,
    );
  }
}

class AdherenceWeekRow {
  const AdherenceWeekRow({required this.weekStart, required this.counts});

  final DateTime weekStart;
  final ({int taken, int expected}) counts;
}

class AdherenceMedicineRow {
  const AdherenceMedicineRow({
    required this.name,
    required this.taken,
    required this.expected,
  });

  final String name;
  final int taken;
  final int expected;
}

class AdherenceScheduleRow {
  const AdherenceScheduleRow({
    required this.title,
    required this.dose,
    required this.schedule,
    required this.status,
    required this.scored,
  });

  final String title;
  final String dose;
  final String schedule;
  final String status;
  final bool scored;
}

class AdherenceUnansweredRow {
  const AdherenceUnansweredRow({
    required this.scheduledAt,
    required this.medicineName,
    required this.statusLabel,
  });

  final DateTime scheduledAt;
  final String medicineName;
  final String statusLabel;
}

class AdherenceCorrectionRow {
  const AdherenceCorrectionRow({
    required this.scheduledAt,
    required this.medicineName,
    required this.note,
  });

  final DateTime scheduledAt;
  final String medicineName;
  final String note;
}

String _statusLabel(Schedule schedule, DateTime now) {
  switch (reminderStatus(schedule, now: now)) {
    case ReminderStatus.active:
      return 'Active';
    case ReminderStatus.paused:
      return 'Paused';
    case ReminderStatus.completed:
      return 'Stopped';
    case ReminderStatus.asNeeded:
      return 'As needed';
  }
}

String? _printableName(String? name) {
  final trimmed = name?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  if (trimmed.contains('@')) return null;
  return trimmed;
}
