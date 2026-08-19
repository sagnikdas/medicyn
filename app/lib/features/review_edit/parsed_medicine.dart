import '../../data/local/tables.dart';
import '../notification_engine/schedule_validation.dart';

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

  /// Builds a [ParsedMedicine] from the edge function's response.
  ///
  /// The tool schema in `parse-medicine` bounds `times`, `daysOfWeek` and
  /// `intervalHours`, but an `input_schema` is guidance to the model, not a
  /// validator the API enforces — so nothing had actually checked these by
  /// the time they reached the database and the alarm scheduler. The OCR text
  /// that produces them comes from whatever was in front of the camera, which
  /// makes it attacker-influenceable.
  ///
  /// Anything unusable is dropped here rather than rejected, because the
  /// review form has to render something for the user to correct. What is
  /// dropped is reflected in [confidence] so the screen presents a
  /// half-understood extraction as exactly that.
  factory ParsedMedicine.fromJson(Map<String, dynamic> json) {
    // Two separate casting hazards, both of which lost the whole extraction:
    // `as List?` throws rather than yielding null when the field is present
    // but of another type, so the shape is tested before it is read; and
    // `.map((e) => e as String)` threw on a list that was mostly strings, so
    // element types are filtered one at a time.
    final timesValue = json['times'];
    final daysValue = json['daysOfWeek'];
    final intervalValue = json['intervalHours'];

    final rawTimes = timesValue is List ? timesValue.whereType<String>().toList() : const <String>[];
    final rawDays =
        daysValue is List ? daysValue.whereType<num>().map((e) => e.toInt()).toList() : const <int>[];
    final rawInterval = intervalValue is num ? intervalValue.toInt() : null;

    final times = schedulableTimes(rawTimes).map((t) => t.label).toList();
    final daysOfWeek = schedulableDays(rawDays);
    // Out of range means the model returned something the user never asked
    // for; carrying it into the form would let it be saved by someone who
    // trusts the screen. Null lets the form fall back to its own default.
    final intervalHours =
        rawInterval == null || schedulableIntervalHours(rawInterval) == null ? null : rawInterval;

    final dropped = times.length != rawTimes.length ||
        daysOfWeek.length != rawDays.length ||
        (rawInterval != null && intervalHours == null);

    final confidenceValue = json['confidence'];
    final statedConfidence = confidenceValue is num ? confidenceValue.toDouble() : 0.0;

    return ParsedMedicine(
      drugName: _text(json['drugName']),
      strength: _text(json['strength']),
      form: _text(json['form']),
      doseAmount: _text(json['doseAmount']),
      frequencyType: _parseFrequency(json['frequencyType']),
      times: times,
      daysOfWeek: daysOfWeek,
      // Was missing, so an "every 8 hours" extraction always arrived with a
      // null interval and the review form silently fell back to its default
      // of 8 — right by luck for 8-hourly doses, wrong for every other one.
      intervalHours: intervalHours,
      notes: _text(json['notes']),
      // A field we had to discard is direct evidence the extraction is not
      // trustworthy, whatever the model said about itself.
      confidence: dropped ? 0 : statedConfidence,
    );
  }

  /// A string field, or '' for anything that is not one.
  ///
  /// `as String?` throws on a field that is present but of another type, so
  /// a numeric drugName used to lose the whole extraction.
  static String _text(Object? value) => value is String ? value : '';

  static FrequencyType _parseFrequency(Object? raw) {
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
