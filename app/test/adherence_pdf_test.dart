import 'package:medicyn/data/export/adherence_pdf.dart';
import 'package:medicyn/data/export/adherence_report.dart';
import 'package:medicyn/data/local/database.dart';
import 'package:medicyn/data/local/tables.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 9, 8, 10);
  final definedAt = now.subtract(const Duration(days: 90));

  ScheduleWithMedicine schedule(String frequency, List<String> times) {
    return ScheduleWithMedicine(
      Schedule(
        id: 's1',
        medicineId: 'm1',
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
        id: 'm1',
        drugName: 'Metformin',
        strength: '500mg',
        form: '',
        doseAmount: '1 tablet',
        notes: '',
        createdAt: definedAt,
        updatedAt: definedAt,
        pendingSync: false,
        deleted: false,
      ),
    );
  }

  test('builds a non-empty PDF for a populated report', () async {
    final report = AdherenceReport.build(
      items: [
        schedule('daily', const ['08:00']),
      ],
      logs: [
        DoseLog(
          id: 'l1',
          scheduleId: 's1',
          scheduledAt: DateTime(2026, 8, 20, 8),
          action: DoseAction.taken.name,
          loggedAt: DateTime(2026, 8, 20, 8),
          source: 'notification',
          pendingSync: false,
        ),
      ],
      now: now,
      patientName: 'Asha Kapoor',
    );

    final bytes = await buildAdherencePdf(report);

    expect(bytes, isNotEmpty);
    // The PDF header (per the spec) always starts with this magic string.
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('builds without throwing when everything is empty', () async {
    // The empty-state copy ("Nothing was due...", "No medicines...") is the
    // one path every other test skips by always seeding at least one
    // schedule -- exercise it directly so a null/empty-list bug in any
    // section doesn't only surface for a brand-new user's first report.
    final report = AdherenceReport.build(
      items: const [],
      logs: const [],
      now: now,
    );
    final bytes = await buildAdherencePdf(report);
    expect(bytes, isNotEmpty);
  });
}
