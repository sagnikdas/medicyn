import 'package:medicyn/features/reminders_home/today_care_store.dart';
import 'package:medicyn/features/review_prescription/parsed_care_item.dart';
import 'package:flutter_test/flutter_test.dart';

/// The model's tool output reaches the review screen through here, and from
/// there `TodayCareStore.save()`. The tool's `input_schema` bounds these
/// fields but does not enforce them, and the OCR text that produces them is
/// whatever was photographed or in the uploaded PDF -- so, same as
/// [ParsedMedicine.fromJson], this is the client-side boundary where the
/// values stop being trusted, even though the edge function already
/// re-validates the same fields server-side.
void main() {
  group('ParsedCareItem.fromJson', () {
    test('keeps a well-formed extraction intact', () {
      final c = ParsedCareItem.fromJson({
        'title': 'Physiotherapy',
        'kind': 'therapy',
        'notes': 'Bring prior scans',
        'firstDate': '2026-09-17',
        'recurrence': 'weekly',
        'intervalN': 1,
        'occurrenceCount': 6,
        'confidence': 0.85,
      });
      expect(c.title, 'Physiotherapy');
      expect(c.kind, TodayCareKind.therapy);
      expect(c.notes, 'Bring prior scans');
      expect(c.firstDate, DateTime(2026, 9, 17));
      expect(c.recurrence, CareRecurrence.weekly);
      expect(c.occurrenceCount, 6);
      expect(c.confidence, 0.85);
    });

    test('defaults an unknown kind to other, matching TodayCareKind.fromName', () {
      final c = ParsedCareItem.fromJson({'title': 'Follow-up', 'kind': 'surgery'});
      expect(c.kind, TodayCareKind.other);
    });

    test('defaults an unknown recurrence to none', () {
      final c = ParsedCareItem.fromJson({'title': 'MRI', 'recurrence': 'biweekly'});
      expect(c.recurrence, CareRecurrence.none);
    });

    test('leaves firstDate null for an unparseable or wrong-shaped date', () {
      expect(ParsedCareItem.fromJson({'firstDate': 'next Tuesday'}).firstDate, isNull);
      expect(ParsedCareItem.fromJson({'firstDate': '2026'}).firstDate, isNull);
      expect(ParsedCareItem.fromJson({'firstDate': ''}).firstDate, isNull);
      expect(ParsedCareItem.fromJson({'firstDate': 42}).firstDate, isNull);
      expect(ParsedCareItem.fromJson({}).firstDate, isNull);
    });

    test('parses a well-formed firstDate', () {
      final c = ParsedCareItem.fromJson({'firstDate': '2026-12-25'});
      expect(c.firstDate, DateTime(2026, 12, 25));
    });

    test('bounds intervalN to 1-365, falling back to 1', () {
      expect(ParsedCareItem.fromJson({'intervalN': 0}).intervalN, 1);
      expect(ParsedCareItem.fromJson({'intervalN': 400}).intervalN, 1);
      expect(ParsedCareItem.fromJson({'intervalN': 2.5}).intervalN, 1);
      expect(ParsedCareItem.fromJson({'intervalN': 90}).intervalN, 90);
      expect(ParsedCareItem.fromJson({}).intervalN, 1);
    });

    test('bounds occurrenceCount to 1-52, falling back to 1', () {
      // A model-supplied 400 would otherwise ask the review screen to
      // render (and the save loop to create) 400 individual reminders.
      expect(ParsedCareItem.fromJson({'occurrenceCount': 0}).occurrenceCount, 1);
      expect(ParsedCareItem.fromJson({'occurrenceCount': 400}).occurrenceCount, 1);
      expect(ParsedCareItem.fromJson({'occurrenceCount': 6}).occurrenceCount, 6);
      expect(ParsedCareItem.fromJson({}).occurrenceCount, 1);
    });

    test('clamps a confidence the model made up', () {
      expect(ParsedCareItem.fromJson({'confidence': 1.5}).confidence, 1.0);
      expect(ParsedCareItem.fromJson({'confidence': -1}).confidence, 0.0);
      expect(ParsedCareItem.fromJson({'confidence': 'high'}).confidence, 0.0);
    });

    test('survives scalar fields of the wrong type', () {
      final c = ParsedCareItem.fromJson({
        'title': 42,
        'notes': ['a', 'b'],
        'kind': 7,
        'recurrence': null,
      });
      expect(c.title, '');
      expect(c.notes, '');
      expect(c.kind, TodayCareKind.other);
      expect(c.recurrence, CareRecurrence.none);
    });

    test('still renders something from an empty response', () {
      final c = ParsedCareItem.fromJson({});
      expect(c.title, '');
      expect(c.kind, TodayCareKind.other);
      expect(c.recurrence, CareRecurrence.none);
      expect(c.firstDate, isNull);
      expect(c.intervalN, 1);
      expect(c.occurrenceCount, 1);
      expect(c.confidence, 0);
    });
  });
}
