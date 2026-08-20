import 'package:dosely/features/care/patient_reminder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> row({
    String drugName = 'Metformin',
    String? strength = '500mg',
    List<String> times = const ['08:00', '20:00'],
    List<int> days = const [],
    Object? intervalHours,
    bool active = true,
    String? medicineUpdatedBy = 'child',
    String? scheduleUpdatedBy = 'child',
  }) =>
      {
        'id': 'sch-1',
        'medicine_id': 'med-1',
        'frequency_type': 'daily',
        'times': times,
        'days_of_week': days,
        'interval_hours': intervalHours,
        'active': active,
        'created_at': '2026-08-01T08:00:00.000Z',
        'updated_at': '2026-08-18T09:00:00.000Z',
        'updated_by': scheduleUpdatedBy,
        'medicines': {
          'id': 'med-1',
          'drug_name': drugName,
          'strength': strength,
          'form': 'tablet',
          'dose_amount': '1 tablet',
          'notes': '',
          'created_at': '2026-08-01T08:00:00.000Z',
          'updated_at': '2026-08-18T09:00:00.000Z',
          'updated_by': medicineUpdatedBy,
        },
      };

  test('unpacks the nested medicine and schedule', () {
    final reminder = PatientReminder.tryParse(row());

    expect(reminder, isNotNull);
    expect(reminder!.title, 'Metformin 500mg');
    expect(reminder.times, ['08:00', '20:00']);
    expect(reminder.medicineUpdatedBy, 'child');
    expect(reminder.asScheduleWithMedicine.medicine.drugName, 'Metformin');
    expect(reminder.asScheduleWithMedicine.schedule.times, ['08:00', '20:00']);
  });

  test('drops the strength from the title when there is none', () {
    expect(PatientReminder.tryParse(row(strength: ''))!.title, 'Metformin');
  });

  test('skips a row whose nested medicine is missing', () {
    expect(
      PatientReminder.tryParse({
        'id': 'sch-1',
        'medicine_id': 'med-1',
        'frequency_type': 'daily',
        'times': ['08:00'],
        'created_at': '2026-08-01T08:00:00.000Z',
        'updated_at': '2026-08-18T09:00:00.000Z',
      }),
      isNull,
    );
  });

  test('accepts interval_hours as a JSON number', () {
    final reminder = PatientReminder.tryParse(row(intervalHours: 8));
    expect(reminder!.intervalHours, 8);
  });
}
