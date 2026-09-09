import 'package:medicyn/data/remote/label_redactor.dart';
import 'package:medicyn/data/remote/prescription_redactor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('redactPrescriptionDocument', () {
    test('strips hospital, MRN, diagnosis and treating doctor from a discharge-style document', () {
      const document = '''
Hospital: City General Hospital
Ward: Cardiology
MRN: A1234567
Patient: John Smith
DOB: 01/15/1950
Diagnosis: Type 2 diabetes mellitus with hypertension
Treating Doctor: Dr. Jane Doe
Metformin 500mg
Take 1 tablet twice daily
Repeat HbA1c in 3 months
''';
      final redacted = redactPrescriptionDocument(document);
      expect(redacted, isNot(contains('City General Hospital')));
      expect(redacted, isNot(contains('Cardiology')));
      expect(redacted, isNot(contains('A1234567')));
      expect(redacted, isNot(contains('John Smith')));
      expect(redacted, isNot(contains('01/15/1950')));
      expect(redacted, isNot(contains('Type 2 diabetes mellitus with hypertension')));
      expect(redacted, isNot(contains('Jane Doe')));
      expect(redacted, contains('Metformin 500mg'));
      expect(redacted, contains('Take 1 tablet twice daily'));
      expect(redacted, contains('Repeat HbA1c in 3 months'));
      expect(redacted, contains(kRedactedLabelToken));
    });

    test('strips MRN, UHID, consultant and diagnosis from an Indian-style document', () {
      const document = '''
Apollo Hospitals
UHID: AH9988776
Consultant: Dr. Sharma
Dx: Hypertension
Metformin 500mg
1-0-1 after food
Repeat scan in 6 months
''';
      final redacted = redactPrescriptionDocument(document);
      expect(redacted, isNot(contains('AH9988776')));
      expect(redacted, isNot(contains('Sharma')));
      expect(redacted, isNot(contains('Hypertension')));
      expect(redacted, contains('Metformin 500mg'));
      expect(redacted, contains('1-0-1 after food'));
      expect(redacted, contains('Repeat scan in 6 months'));
    });

    test('strips department, admitting doctor and referred-by lines', () {
      const document = '''
Department: Orthopedics
Admitting Doctor: Dr. Lee
Referred by: Dr. Patel
Physiotherapy, once a week, 6 sessions
''';
      final redacted = redactPrescriptionDocument(document);
      expect(redacted, isNot(contains('Orthopedics')));
      expect(redacted, isNot(contains('Lee')));
      expect(redacted, isNot(contains('Patel')));
      expect(redacted, contains('Physiotherapy, once a week, 6 sessions'));
    });

    test('keeps Generic Name / Brand Name / Drug Name as the medicine, not a clinical label', () {
      const document = '''
Generic Name: Metformin Hydrochloride
Drug Name: Glucophage
Diagnosis: Type 2 diabetes
''';
      final redacted = redactPrescriptionDocument(document);
      expect(redacted, contains('Metformin Hydrochloride'));
      expect(redacted, contains('Glucophage'));
      expect(redacted, isNot(contains('Type 2 diabetes')));
    });

    test('still runs the base pharmacy-label redaction (name, address, phone, Rx)', () {
      const document = '''
Hospital: City General
Rx# 1234567
Patient: John Smith
123 Main Street
john.smith@example.com
(555) 123-4567
Metformin 500mg
''';
      final redacted = redactPrescriptionDocument(document);
      expect(redacted, isNot(contains('City General')));
      expect(redacted, isNot(contains('1234567')));
      expect(redacted, isNot(contains('John Smith')));
      expect(redacted, isNot(contains('123 Main')));
      expect(redacted, isNot(contains('john.smith@example.com')));
      expect(redacted, isNot(contains('555')));
      expect(redacted, contains('Metformin 500mg'));
    });

    test('leaves a document with only medicines and instructions unchanged', () {
      const document = 'Metformin 500mg\nTake 1 tablet twice daily with food';
      expect(redactPrescriptionDocument(document), document);
    });

    test('returns empty input unchanged', () {
      expect(redactPrescriptionDocument(''), '');
    });
  });
}
