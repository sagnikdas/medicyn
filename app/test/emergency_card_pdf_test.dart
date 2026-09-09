import 'package:flutter_test/flutter_test.dart';
import 'package:medicyn/data/export/emergency_card_data.dart';
import 'package:medicyn/data/export/emergency_card_pdf.dart';

void main() {
  test('builds a non-empty PDF for a populated card', () async {
    final data = EmergencyCardData(
      generatedAt: DateTime(2026, 9, 8, 10),
      patientName: 'Asha Kapoor',
      bloodGroup: 'O+',
      allergies: 'Penicillin, peanuts',
      allergiesSevere: true,
      conditions: 'Type 2 diabetes',
      notes: 'Pacemaker fitted 2022',
      insuranceNumber: 'INS-4471',
      nationalId: '1234 5678 9012',
      healthCardNumber: 'HC-88213',
      emergencyContactName: 'Priya Kapoor',
      emergencyContactPhone: '+919876500000',
      medicines: const [
        EmergencyMedicineRow(title: 'Metformin 500mg', dose: '1 tablet'),
      ],
      caregiverName: 'Rohit Kapoor',
      caregiverPhone: '+919876543210',
      updatedAt: DateTime(2026, 9, 1),
    );

    final bytes = await buildEmergencyCardPdf(data);

    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('builds without throwing when everything is empty', () async {
    final data = EmergencyCardData(
      generatedAt: DateTime(2026, 9, 8, 10),
      patientName: null,
      bloodGroup: '',
      allergies: '',
      allergiesSevere: false,
      conditions: '',
      notes: '',
      insuranceNumber: '',
      nationalId: '',
      healthCardNumber: '',
      emergencyContactName: '',
      emergencyContactPhone: '',
      medicines: const [],
      caregiverName: null,
      caregiverPhone: null,
      updatedAt: null,
    );

    final bytes = await buildEmergencyCardPdf(data);
    expect(bytes, isNotEmpty);
  });
}
