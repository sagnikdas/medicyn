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
      conditions: 'Type 2 diabetes',
      medicines: const [
        EmergencyMedicineRow(title: 'Metformin 500mg', dose: '1 tablet'),
      ],
      caregiverPhone: '+919876543210',
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
      conditions: '',
      medicines: const [],
      caregiverPhone: null,
    );

    final bytes = await buildEmergencyCardPdf(data);
    expect(bytes, isNotEmpty);
  });
}
