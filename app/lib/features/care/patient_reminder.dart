import '../../data/local/database.dart';

/// One of a patient's medicines as Postgres stores it, unpacked from the
/// nested PostgREST shape the caregiver list reads.
///
/// Kept off the caregiver's local Drift file on purpose: that file is
/// encrypted per signed-in account, and mixing a parent's rows into it would
/// show the wrong person's medicines after a sign-out. The review form still
/// wants a [ScheduleWithMedicine], so [asScheduleWithMedicine] builds one
/// in memory without writing it anywhere.
class PatientReminder {
  const PatientReminder({
    required this.medicineId,
    required this.scheduleId,
    required this.drugName,
    required this.strength,
    required this.form,
    required this.doseAmount,
    required this.notes,
    required this.frequencyType,
    required this.times,
    required this.daysOfWeek,
    required this.intervalHours,
    required this.active,
    required this.medicineCreatedAt,
    required this.scheduleCreatedAt,
    required this.medicineUpdatedAt,
    required this.scheduleUpdatedAt,
    required this.medicineUpdatedBy,
    required this.scheduleUpdatedBy,
  });

  final String medicineId;
  final String scheduleId;
  final String drugName;
  final String strength;
  final String form;
  final String doseAmount;
  final String notes;
  final String frequencyType;
  final List<String> times;
  final List<int> daysOfWeek;
  final int? intervalHours;
  final bool active;
  final DateTime medicineCreatedAt;
  final DateTime scheduleCreatedAt;
  final DateTime medicineUpdatedAt;
  final DateTime scheduleUpdatedAt;
  final String? medicineUpdatedBy;
  final String? scheduleUpdatedBy;

  String get title => strength.isEmpty ? drugName : '$drugName $strength';

  Medicine get medicine => Medicine(
        id: medicineId,
        drugName: drugName,
        strength: strength,
        form: form,
        doseAmount: doseAmount,
        notes: notes,
        createdAt: medicineCreatedAt,
        updatedAt: medicineUpdatedAt,
        updatedBy: medicineUpdatedBy,
        pendingSync: false,
        deleted: false,
      );

  Schedule get schedule => Schedule(
        id: scheduleId,
        medicineId: medicineId,
        frequencyType: frequencyType,
        times: times,
        daysOfWeek: daysOfWeek,
        intervalHours: intervalHours,
        active: active,
        createdAt: scheduleCreatedAt,
        updatedAt: scheduleUpdatedAt,
        updatedBy: scheduleUpdatedBy,
        pendingSync: false,
        deleted: false,
      );

  ScheduleWithMedicine get asScheduleWithMedicine =>
      ScheduleWithMedicine(schedule, medicine);

  /// Null when the nested medicine is missing — a malformed response, not a
  /// normal empty list. The caller skips the row rather than crashing the list.
  static PatientReminder? tryParse(Map<String, dynamic> row) {
    final medicine = (row['medicines'] as Map?)?.cast<String, dynamic>();
    if (medicine == null) return null;
    final scheduleId = row['id'] as String?;
    final medicineId = (row['medicine_id'] as String?) ?? medicine['id'] as String?;
    final drugName = medicine['drug_name'] as String?;
    if (scheduleId == null || medicineId == null || drugName == null) return null;

    return PatientReminder(
      medicineId: medicineId,
      scheduleId: scheduleId,
      drugName: drugName,
      strength: (medicine['strength'] as String?) ?? '',
      form: (medicine['form'] as String?) ?? '',
      doseAmount: (medicine['dose_amount'] as String?) ?? '',
      notes: (medicine['notes'] as String?) ?? '',
      frequencyType: (row['frequency_type'] as String?) ?? '',
      times: (row['times'] as List?)?.whereType<String>().toList() ?? const [],
      daysOfWeek: (row['days_of_week'] as List?)
              ?.whereType<num>()
              .map((e) => e.toInt())
              .toList() ??
          const [],
      intervalHours: _intOrNull(row['interval_hours']),
      active: row['active'] as bool? ?? true,
      medicineCreatedAt: _stamp(medicine, 'created_at'),
      scheduleCreatedAt: _stamp(row, 'created_at'),
      medicineUpdatedAt: _stamp(medicine, 'updated_at', fallbackKey: 'created_at'),
      scheduleUpdatedAt: _stamp(row, 'updated_at', fallbackKey: 'created_at'),
      medicineUpdatedBy: medicine['updated_by'] as String?,
      scheduleUpdatedBy: row['updated_by'] as String?,
    );
  }

  static int? _intOrNull(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  static DateTime _stamp(
    Map<String, dynamic> row,
    String key, {
    String? fallbackKey,
  }) {
    final raw = (row[key] as String?) ??
        (fallbackKey == null ? null : row[fallbackKey] as String?);
    if (raw == null) {
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }
    return DateTime.parse(raw);
  }
}
