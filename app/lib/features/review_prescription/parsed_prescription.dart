import '../review_edit/parsed_medicine.dart';
import 'parsed_care_item.dart';

/// The `parse-prescription` edge function's full response: every medicine
/// and every care item detected in one document. Deserializes `medicines`
/// with the *existing* [ParsedMedicine.fromJson] unchanged -- the two
/// extraction contracts share that shape exactly -- so a fix to time/day/
/// interval validation there applies to both the single-item and
/// multi-item flows without a second copy to drift out of sync.
class ParsedPrescription {
  final List<ParsedMedicine> medicines;
  final List<ParsedCareItem> careItems;

  const ParsedPrescription({
    this.medicines = const [],
    this.careItems = const [],
  });

  factory ParsedPrescription.fromJson(Map<String, dynamic> json) {
    final medicinesValue = json['medicines'];
    final careItemsValue = json['careItems'];

    final medicines = medicinesValue is List
        ? medicinesValue
              .whereType<Map>()
              .map((m) => ParsedMedicine.fromJson(m.cast<String, dynamic>()))
              .toList()
        : const <ParsedMedicine>[];

    final careItems = careItemsValue is List
        ? careItemsValue
              .whereType<Map>()
              .map((c) => ParsedCareItem.fromJson(c.cast<String, dynamic>()))
              .toList()
        : const <ParsedCareItem>[];

    return ParsedPrescription(medicines: medicines, careItems: careItems);
  }

  bool get isEmpty => medicines.isEmpty && careItems.isEmpty;
}
