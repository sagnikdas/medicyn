import '../../data/local/tables.dart';

/// Mirrors the `extract_medicine_schedule` tool schema the `parse-medicine`
/// edge function forces Claude to fill in. Every field has a safe default
/// so a partial/low-confidence extraction still renders an editable form
/// instead of crashing.
class ParsedMedicine {
  final String drugName;
  final String strength;
  final String form;
  final String doseAmount;
  final FrequencyType frequencyType;
  final List<String> times;
  final List<int> daysOfWeek;
  final int? intervalHours;
  final String notes;
  final double confidence;

  const ParsedMedicine({
    this.drugName = '',
    this.strength = '',
    this.form = '',
    this.doseAmount = '',
    this.frequencyType = FrequencyType.daily,
    this.times = const [],
    this.daysOfWeek = const [],
    this.intervalHours,
    this.notes = '',
    this.confidence = 0,
  });

  factory ParsedMedicine.fromJson(Map<String, dynamic> json) {
    return ParsedMedicine(
      drugName: json['drugName'] as String? ?? '',
      strength: json['strength'] as String? ?? '',
      form: json['form'] as String? ?? '',
      doseAmount: json['doseAmount'] as String? ?? '',
      frequencyType: _parseFrequency(json['frequencyType'] as String?),
      times: (json['times'] as List?)?.map((e) => e as String).toList() ?? const [],
      daysOfWeek: (json['daysOfWeek'] as List?)?.map((e) => e as int).toList() ?? const [],
      notes: json['notes'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
    );
  }

  static FrequencyType _parseFrequency(String? raw) {
    switch (raw) {
      case 'specific_days':
        return FrequencyType.specificDays;
      case 'every_x_hours':
        return FrequencyType.everyXHours;
      case 'as_needed':
        return FrequencyType.asNeeded;
      case 'daily':
      default:
        return FrequencyType.daily;
    }
  }
}
