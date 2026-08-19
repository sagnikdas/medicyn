import 'package:dosely/data/local/tables.dart';
import 'package:dosely/features/review_edit/parsed_medicine.dart';
import 'package:flutter_test/flutter_test.dart';

/// The model's tool output reaches the review form through here, and from
/// there the database and the alarm scheduler. The tool's `input_schema`
/// bounds these fields but does not enforce them, and half the input is OCR
/// of whatever was in front of the camera — so this is the boundary where
/// the values stop being trusted.
void main() {
  group('ParsedMedicine.fromJson', () {
    test('keeps a well-formed extraction intact', () {
      final p = ParsedMedicine.fromJson({
        'drugName': 'Metformin',
        'strength': '500mg',
        'doseAmount': '1 tablet',
        'frequencyType': 'specific_days',
        'times': ['08:00', '20:00'],
        'daysOfWeek': [1, 3, 5],
        'confidence': 0.9,
      });
      expect(p.drugName, 'Metformin');
      expect(p.frequencyType, FrequencyType.specificDays);
      expect(p.times, ['08:00', '20:00']);
      expect(p.daysOfWeek, [1, 3, 5]);
      expect(p.confidence, 0.9);
    });

    test('drops a day the review form cannot draw a chip for', () {
      // The form renders exactly seven chips, so a 9 was invisible there:
      // it could not be seen or deselected, and went straight to the
      // scheduler, where it hung the walk looking for a matching weekday.
      final p = ParsedMedicine.fromJson({'daysOfWeek': [1, 9, 5]});
      expect(p.daysOfWeek, [1, 5]);
    });

    test('drops a malformed time and keeps the rest', () {
      final p = ParsedMedicine.fromJson({'times': ['08:00', '9am', '29:00', '20:30']});
      expect(p.times, ['08:00', '20:30']);
    });

    test('discards an out-of-range interval instead of carrying it into the form', () {
      expect(ParsedMedicine.fromJson({'intervalHours': 0}).intervalHours, isNull);
      expect(ParsedMedicine.fromJson({'intervalHours': 99}).intervalHours, isNull);
      expect(ParsedMedicine.fromJson({'intervalHours': 8}).intervalHours, 8);
    });

    test('reports no confidence when it had to discard something', () {
      // A field we could not use is direct evidence the extraction is not
      // trustworthy, whatever the model claimed about itself.
      final p = ParsedMedicine.fromJson({
        'times': ['08:00', '29:00'],
        'confidence': 0.95,
      });
      expect(p.confidence, 0);
    });

    test('keeps the stated confidence when nothing was discarded', () {
      final p = ParsedMedicine.fromJson({
        'times': ['08:00'],
        'confidence': 0.95,
      });
      expect(p.confidence, 0.95);
    });

    test('survives a list whose elements are the wrong type', () {
      // `.map((e) => e as String)` threw on this and lost the whole
      // extraction over one bad entry.
      final p = ParsedMedicine.fromJson({
        'times': ['08:00', 42, null],
        'daysOfWeek': [1, 'two', 3],
      });
      expect(p.times, ['08:00']);
      expect(p.daysOfWeek, [1, 3]);
    });

    test('survives fields of entirely the wrong shape', () {
      final p = ParsedMedicine.fromJson({'times': '08:00', 'daysOfWeek': 3});
      expect(p.times, isEmpty);
      expect(p.daysOfWeek, isEmpty);
    });

    test('survives a scalar field of the wrong type', () {
      // `as String?` throws on a present-but-wrong-typed field, so a numeric
      // drugName lost the whole extraction rather than one field.
      final p = ParsedMedicine.fromJson({
        'drugName': 42,
        'notes': ['a', 'b'],
        'confidence': 'high',
      });
      expect(p.drugName, '');
      expect(p.notes, '');
      expect(p.confidence, 0);
    });

    test('falls back to daily for a frequency it does not know', () {
      expect(ParsedMedicine.fromJson({'frequencyType': 'hourly'}).frequencyType, FrequencyType.daily);
      expect(ParsedMedicine.fromJson({}).frequencyType, FrequencyType.daily);
    });

    test('still renders something from an empty response', () {
      // The form has to have something to show; rejecting outright would
      // leave the user with nothing to correct.
      final p = ParsedMedicine.fromJson({});
      expect(p.drugName, '');
      expect(p.times, isEmpty);
      expect(p.confidence, 0);
    });
  });
}
