import '../reminders_home/today_care_store.dart';

/// How a [ParsedCareItem] repeats. Mirrors the `parse-prescription` edge
/// function's `recurrence` values. This is only a hint for how many dated
/// reminders to generate at review time (see `care_recurrence.dart`) --
/// [TodayCareReminders] itself has no recurrence concept, and none is added
/// by this feature; each generated reminder is an ordinary one-off row.
enum CareRecurrence {
  none,
  weekly,
  everyNDays,
  everyNMonths;

  static CareRecurrence fromName(String value) => switch (value) {
    'weekly' => CareRecurrence.weekly,
    'every_n_days' => CareRecurrence.everyNDays,
    'every_n_months' => CareRecurrence.everyNMonths,
    _ => CareRecurrence.none,
  };
}

/// Mirrors one element of the `careItems` array in `parse-prescription`'s
/// tool schema. Every field has a safe default so a partial/low-confidence
/// extraction still renders an editable row instead of crashing -- same
/// contract as [ParsedMedicine].
class ParsedCareItem {
  final String title;
  final TodayCareKind kind;
  final String notes;

  /// Null if the model gave no usable date; [expandCareOccurrences] falls
  /// back to a sensible default when this is null.
  final DateTime? firstDate;
  final CareRecurrence recurrence;

  /// Meaningful only for [CareRecurrence.everyNDays]/[CareRecurrence.everyNMonths].
  final int intervalN;

  /// Total reminders to generate, including the first. Always >= 1.
  final int occurrenceCount;
  final double confidence;

  const ParsedCareItem({
    this.title = '',
    this.kind = TodayCareKind.other,
    this.notes = '',
    this.firstDate,
    this.recurrence = CareRecurrence.none,
    this.intervalN = 1,
    this.occurrenceCount = 1,
    this.confidence = 0,
  });

  /// Builds a [ParsedCareItem] from the edge function's response.
  ///
  /// The tool schema bounds every numeric/enum field, but an `input_schema`
  /// is guidance to the model, not a validator the API enforces -- the
  /// server-side `sanitiseExtraction` already re-checks all of this, and
  /// the client re-checks it again here for the same reason
  /// `ParsedMedicine.fromJson` does: an old build is still out there, and
  /// this is not the only writer of what eventually arms a real alarm.
  factory ParsedCareItem.fromJson(Map<String, dynamic> json) {
    final intervalValue = json['intervalN'];
    final countValue = json['occurrenceCount'];
    final confidenceValue = json['confidence'];

    return ParsedCareItem(
      title: _text(json['title']),
      kind: json['kind'] is String
          ? TodayCareKind.fromName(json['kind'] as String)
          : TodayCareKind.other,
      notes: _text(json['notes']),
      firstDate: _date(json['firstDate']),
      recurrence: json['recurrence'] is String
          ? CareRecurrence.fromName(json['recurrence'] as String)
          : CareRecurrence.none,
      intervalN: _boundedInt(intervalValue, min: 1, max: 365, fallback: 1),
      occurrenceCount: _boundedInt(countValue, min: 1, max: 52, fallback: 1),
      confidence: confidenceValue is num
          ? confidenceValue.toDouble().clamp(0, 1)
          : 0.0,
    );
  }

  /// A string field, or '' for anything that is not one.
  static String _text(Object? value) => value is String ? value : '';

  /// `YYYY-MM-DD`, or null for anything else -- including a malformed
  /// string, which `DateTime.tryParse` would otherwise accept in forms this
  /// field is never meant to carry (e.g. it also parses bare "2026").
  static DateTime? _date(Object? value) {
    if (value is! String) return null;
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return null;
    return DateTime.tryParse(value);
  }

  static int _boundedInt(
    Object? value, {
    required int min,
    required int max,
    required int fallback,
  }) {
    if (value is! num) return fallback;
    final intValue = value.toInt();
    if (intValue != value || intValue < min || intValue > max) return fallback;
    return intValue;
  }
}
