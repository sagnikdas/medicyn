import 'package:dosely/features/care/care_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// [CareLink] decides which of two people is looking at a link and therefore
/// which screen they get. Getting `isPatient` backwards would show the person
/// needing help the caregiver's view, so it is worth pinning down.
void main() {
  const patient = '11111111-1111-1111-1111-111111111111';
  const caregiver = '22222222-2222-2222-2222-222222222222';

  Map<String, dynamic> row({
    String status = 'active',
    String? caregiverId = caregiver,
    String? code,
    String? expiresAt,
  }) =>
      {
        'id': 'link-1',
        'patient_id': patient,
        'caregiver_id': caregiverId,
        'status': status,
        'invite_code': code,
        'expires_at': expiresAt,
      };

  group('fromRow', () {
    test('reads an active link', () {
      final link = CareLink.fromRow(row());

      expect(link.id, 'link-1');
      expect(link.status, CareLinkStatus.active);
      expect(link.patientId, patient);
      expect(link.caregiverId, caregiver);
    });

    test('reads an unclaimed invite, which has no caregiver yet', () {
      final link = CareLink.fromRow(
        row(status: 'pending', caregiverId: null, code: '048213'),
      );

      expect(link.status, CareLinkStatus.pending);
      expect(link.caregiverId, isNull);
      expect(link.inviteCode, '048213');
    });

    test('parses every status the database can produce', () {
      for (final status in CareLinkStatus.values) {
        expect(CareLink.fromRow(row(status: status.name)).status, status);
      }
    });

    test('brings the expiry into local time', () {
      final link = CareLink.fromRow(row(expiresAt: '2026-08-18T16:30:00.000Z'));

      expect(link.expiresAt, isNotNull);
      expect(link.expiresAt!.isUtc, isFalse);
      expect(
        link.expiresAt!.toUtc(),
        DateTime.utc(2026, 8, 18, 16, 30),
      );
    });

    test('leaves a null expiry null rather than inventing one', () {
      expect(CareLink.fromRow(row()).expiresAt, isNull);
    });
  });

  group('point of view', () {
    test('identifies the patient', () {
      final link = CareLink.fromRow(row());

      expect(link.isPatient(patient), isTrue);
      expect(link.isPatient(caregiver), isFalse);
    });

    test('names the other party from either side', () {
      final link = CareLink.fromRow(row());

      expect(link.otherPartyId(patient), caregiver);
      expect(link.otherPartyId(caregiver), patient);
    });

    test('has no other party while an invite is unclaimed', () {
      final link = CareLink.fromRow(row(status: 'pending', caregiverId: null));

      expect(link.otherPartyId(patient), isNull);
    });
  });
}
