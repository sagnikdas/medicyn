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
        row(status: 'pending', caregiverId: null, code: '04821300'),
      );

      expect(link.status, CareLinkStatus.pending);
      expect(link.caregiverId, isNull);
      expect(link.inviteCode, '04821300');
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

  group('CareClaimant.tryParse', () {
    test('accepts a single row with name and email', () {
      final claimant = CareClaimant.tryParse([
        {'display_name': 'Priya', 'email': 'priya@test.invalid'},
      ]);

      expect(claimant, isNotNull);
      expect(claimant!.displayName, 'Priya');
      expect(claimant.email, 'priya@test.invalid');
    });

    test('accepts a bare map, which some RPC clients return for one row', () {
      final claimant = CareClaimant.tryParse({
        'display_name': 'Priya',
        'email': 'priya@test.invalid',
      });

      expect(claimant?.displayName, 'Priya');
    });

    test('fails closed when the rpc returned nothing', () {
      expect(CareClaimant.tryParse([]), isNull);
      expect(CareClaimant.tryParse(null), isNull);
    });

    test('fails closed when the display name is missing', () {
      expect(
        CareClaimant.tryParse([
          {'display_name': null, 'email': 'priya@test.invalid'},
        ]),
        isNull,
      );
      expect(
        CareClaimant.tryParse([
          {'display_name': '  ', 'email': 'priya@test.invalid'},
        ]),
        isNull,
      );
    });

    test('fails closed when the email is missing — a name alone is not enough', () {
      expect(
        CareClaimant.tryParse([
          {'display_name': 'Priya', 'email': null},
        ]),
        isNull,
      );
    });
  });

  group('reminderFromRow', () {
    Map<String, dynamic> row() => {
          'id': 'sched-1',
          'medicine_id': 'med-1',
          'frequency_type': 'daily',
          'times': ['09:00', '21:00'],
          'days_of_week': <int>[],
          'interval_hours': null,
          'active': true,
          'created_at': '2026-08-18T08:00:00.000Z',
          'updated_at': '2026-08-19T10:00:00.000Z',
          'updated_by': caregiver,
          'medicines': {
            'id': 'med-1',
            'drug_name': 'Metformin',
            'strength': '500mg',
            'form': 'tablet',
            'dose_amount': '1 tablet',
            'notes': '',
            'created_at': '2026-08-18T08:00:00.000Z',
            'updated_at': '2026-08-19T10:00:00.000Z',
            'updated_by': caregiver,
          },
        };

    test('unpacks a nested medicine and schedule', () {
      final parsed = CareService.reminderFromRow(row());
      expect(parsed, isNotNull);
      expect(parsed!.medicine.drugName, 'Metformin');
      expect(parsed.schedule.times, ['09:00', '21:00']);
      expect(parsed.schedule.updatedBy, caregiver);
    });

    test('drops a schedule that cannot be armed', () {
      final bad = row();
      bad['frequency_type'] = 'hourly';
      expect(CareService.reminderFromRow(bad), isNull);
    });
  });
}
