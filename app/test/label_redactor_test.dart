import 'package:medicyn/data/remote/label_redactor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('redactPharmacyLabel', () {
    test(
      'strips name, address, DoB, Rx and prescriber from a US-style label',
      () {
        const label = '''
WALGREENS
Rx# 1234567
Patient: John Smith
123 Main Street
Springfield, CA 90210
DOB: 01/15/1950
Prescriber: Dr. Jane Doe
Metformin HCl 500 MG Tablet
Take 1 tablet by mouth twice daily
Qty: 60
Exp: 08/2027
''';
        final redacted = redactPharmacyLabel(label);
        expect(redacted, isNot(contains('John Smith')));
        expect(redacted, isNot(contains('123 Main')));
        expect(redacted, isNot(contains('90210')));
        expect(redacted, isNot(contains('01/15/1950')));
        expect(redacted, isNot(contains('1234567')));
        expect(redacted, isNot(contains('Jane Doe')));
        expect(redacted, contains('Metformin HCl 500 MG Tablet'));
        expect(redacted, contains('Take 1 tablet by mouth twice daily'));
        expect(redacted, contains('Qty: 60'));
        expect(redacted, contains('Exp: 08/2027'));
        expect(redacted, contains(kRedactedLabelToken));
      },
    );

    test('strips the same identifiers from an Indian-style label', () {
      const label = '''
Apollo Pharmacy
Patient: RAMESH KUMAR
Age/Sex: 67/M
Rx No: 987654
Prescribed by: Dr. Sharma
Address: 12 MG Road
Metformin 500mg
Tab
1-0-1 after food
''';
      final redacted = redactPharmacyLabel(label);
      expect(redacted, isNot(contains('RAMESH')));
      expect(redacted, isNot(contains('67/M')));
      expect(redacted, isNot(contains('987654')));
      expect(redacted, isNot(contains('Sharma')));
      expect(redacted, isNot(contains('12 MG Road')));
      expect(redacted, contains('Metformin 500mg'));
      expect(redacted, contains('1-0-1 after food'));
    });

    test('leaves a label that is only medicine and directions unchanged', () {
      const label = 'Metformin 500mg\nTake 1 tablet twice daily with food';
      expect(redactPharmacyLabel(label), label);
    });

    test('does not treat Rx only as a prescription number', () {
      const label = 'Metformin 500mg\nRx only\nTake 1 tablet daily';
      expect(redactPharmacyLabel(label), label);
    });

    test(
      'keeps Generic Name / Brand Name as the medicine, not the patient',
      () {
        const label = '''
Generic Name: Metformin Hydrochloride
Brand Name: Glucophage
Patient Name: Priya Nair
''';
        final redacted = redactPharmacyLabel(label);
        expect(redacted, contains('Metformin Hydrochloride'));
        expect(redacted, contains('Glucophage'));
        expect(redacted, isNot(contains('Priya Nair')));
      },
    );

    test('redacts an email and a phone number left on the label', () {
      const label = '''
Metformin 500mg
john.smith@example.com
(555) 123-4567
Take 1 tablet daily
''';
      final redacted = redactPharmacyLabel(label);
      expect(redacted, isNot(contains('john.smith@example.com')));
      expect(redacted, isNot(contains('555')));
      expect(redacted, contains('Metformin 500mg'));
    });

    test('returns empty input unchanged', () {
      expect(redactPharmacyLabel(''), '');
    });
  });
}
