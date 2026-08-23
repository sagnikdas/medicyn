import 'package:dosely/features/care/care_service.dart';
import 'package:dosely/data/local/tables.dart';
import 'package:flutter_test/flutter_test.dart';

/// Everything here parses a row written by *another* device, or by Postgres,
/// and hands it to a screen a worried relative reads. Fail-closed matters
/// more than fail-soft: naming the wrong person on a consent prompt, or
/// showing a reminder whose schedule cannot actually fire, is worse than
/// showing nothing.
void main() {
  group('CareClaimant.tryParse', () {
    Map<String, dynamic> claimant({
      Object? name = 'Priya',
      Object? email = 'priya@example.com',
    }) =>
        {'display_name': name, 'email': email};

    test('reads a bare object', () {
      final c = CareClaimant.tryParse(claimant());
      expect(c?.displayName, 'Priya');
      expect(c?.email, 'priya@example.com');
    });

    test('reads the first row of a PostgREST list', () {
      final c = CareClaimant.tryParse([claimant()]);
      expect(c?.displayName, 'Priya');
    });

    test('refuses to name anyone when the name is missing', () {
      expect(CareClaimant.tryParse(claimant(name: null)), isNull);
    });

    test('refuses to name anyone when the email is missing', () {
      expect(CareClaimant.tryParse(claimant(email: null)), isNull);
    });

    test('treats whitespace as absent rather than confirming a blank person', () {
      expect(CareClaimant.tryParse(claimant(name: '   ')), isNull);
      expect(CareClaimant.tryParse(claimant(email: '  ')), isNull);
    });

    test('trims what it does accept', () {
      final c = CareClaimant.tryParse(claimant(name: '  Priya  '));
      expect(c?.displayName, 'Priya');
    });

    test('returns null for an empty list, null, or a wrong-typed payload', () {
      expect(CareClaimant.tryParse(const []), isNull);
      expect(CareClaimant.tryParse(null), isNull);
      expect(CareClaimant.tryParse('Priya'), isNull);
      expect(CareClaimant.tryParse(const [42]), isNull);
    });
  });

  group('claimInviteError', () {
    test('surfaces the code the database committed', () {
      expect(CareService.claimInviteError({'error': 'already_linked'}),
          'already_linked');
    });

    test('reads success as no error', () {
      expect(CareService.claimInviteError({'link_id': 'abc'}), isNull);
      expect(CareService.claimInviteError(null), isNull);
      expect(CareService.claimInviteError({'error': ''}), isNull);
      expect(CareService.claimInviteError({'error': 42}), isNull);
    });
  });

  group('CareProfile.remindersMayNotFire', () {
    CareProfile profile({
      bool? notifications = true,
      bool? exactAlarms = true,
      bool? battery = true,
      int? armed = 4,
    }) =>
        CareProfile(
          userId: 'u',
          notificationsAllowed: notifications,
          exactAlarmsAllowed: exactAlarms,
          batteryExemption: battery,
          armedAlarmCount: armed,
        );

    test('a healthy device raises nothing', () {
      expect(profile().remindersMayNotFire, isFalse);
    });

    test('each permission that is off on its own is enough to warn', () {
      expect(profile(notifications: false).remindersMayNotFire, isTrue);
      expect(profile(exactAlarms: false).remindersMayNotFire, isTrue);
      expect(profile(battery: false).remindersMayNotFire, isTrue);
    });

    test('no armed alarms at all is a warning', () {
      expect(profile(armed: 0).remindersMayNotFire, isTrue);
    });

    test('unknown is not the same as off, so an old profile stays quiet', () {
      expect(
        profile(notifications: null, exactAlarms: null, battery: null, armed: null)
            .remindersMayNotFire,
        isFalse,
      );
    });
  });

  group('MedicineEdit.fromRow', () {
    Map<String, dynamic> row({Object? summary = 'Changed the time'}) => {
          'id': 'edit-1',
          'medicine_id': 'med-1',
          'owner_id': 'owner-1',
          'actor_id': 'actor-1',
          'summary': summary,
          'created_at': '2026-08-18T16:30:00Z',
        };

    test('reads an edit made by the other side of the link', () {
      final e = MedicineEdit.fromRow(row());
      expect(e.medicineId, 'med-1');
      expect(e.actorId, 'actor-1');
      expect(e.summary, 'Changed the time');
      expect(e.createdAt.toUtc(), DateTime.utc(2026, 8, 18, 16, 30));
    });

    test('a summary the database never wrote reads as empty, not null', () {
      expect(MedicineEdit.fromRow(row(summary: null)).summary, '');
    });
  });

  group('reminderFromRow', () {
    Map<String, dynamic> medicine({String? name = 'Metformin'}) => {
          'id': 'med-1',
          'drug_name': name,
          'strength': '500mg',
          'form': 'tablet',
          'dose_amount': '1 tablet',
          'notes': '',
          'tablets_remaining': 30,
          'tablets_per_dose': 1,
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-08-01T00:00:00Z',
          'updated_by': 'someone',
        };

    Map<String, dynamic> row({
      Object? frequency = 'daily',
      Object? times = const ['08:00'],
      Object? days = const <int>[],
      Object? interval,
      Object? active = true,
      Map<String, dynamic>? med,
      bool withMedicine = true,
    }) =>
        {
          'id': 'sched-1',
          'frequency_type': frequency,
          'times': times,
          'days_of_week': days,
          'interval_hours': interval,
          'active': active,
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-08-02T00:00:00Z',
          'updated_by': 'someone',
          if (withMedicine) 'medicines': med ?? medicine(),
        };

    test('reads a daily reminder the caregiver can display', () {
      final r = CareService.reminderFromRow(row())!;
      expect(r.medicine.drugName, 'Metformin');
      expect(r.schedule.frequencyType, FrequencyType.daily.name);
      expect(r.schedule.times, ['08:00']);
      expect(r.medicine.tabletsRemaining, 30);
    });

    test('drops a row with no medicine rather than inventing one', () {
      expect(CareService.reminderFromRow(row(withMedicine: false)), isNull);
    });

    test('drops a schedule whose stored values could never be armed', () {
      // An every-X-hours row with a zero interval is a walk that never
      // advances, and an unknown frequency names no scheduler at all.
      expect(
        CareService.reminderFromRow(
          row(frequency: 'everyXHours', interval: 0, times: const ['08:00']),
        ),
        isNull,
      );
      expect(CareService.reminderFromRow(row(frequency: 'nonsense')), isNull);
      expect(CareService.reminderFromRow(row(frequency: null)), isNull);
    });

    test('an unparseable time is dropped, keeping the times that work', () {
      final r = CareService.reminderFromRow(
        row(times: const ['08:00', '29:00', 'noon', '20:30']),
      )!;
      expect(r.schedule.times, ['08:00', '20:30']);
    });

    test('a day outside 0..6 is dropped rather than arming nothing', () {
      final r = CareService.reminderFromRow(
        row(frequency: 'specificDays', days: const [1, 9, 5]),
      )!;
      expect(r.schedule.daysOfWeek, [1, 5]);
    });

    // Known gap, not an assertion that this is right: sanitiseScheduleFields
    // is deliberately value-domain only, so a daily row whose `times` is
    // empty is accepted and shown as a live reminder that can never fire.
    // The cross-field rule was deferred on purpose — see the "Deliberately
    // not added" note in 20260819140000_schedule_field_constraints.sql.
    test('an empty times array is currently accepted, firing nothing', () {
      final r = CareService.reminderFromRow(row(times: const []));
      expect(r, isNotNull);
      expect(r!.schedule.times, isEmpty);
    });

    test('a medicine with no name still reads, under a neutral label', () {
      final r = CareService.reminderFromRow(row(med: medicine(name: null)))!;
      expect(r.medicine.drugName, 'Medicine');
    });

    test('a missing schedule timestamp falls back to the medicine, not to now', () {
      final bare = row()..remove('updated_at');
      final r = CareService.reminderFromRow(bare)!;
      expect(r.schedule.updatedAt.toUtc(), DateTime.utc(2026, 8, 1));
    });

    test('active defaults to true when the column is absent', () {
      final bare = row()..remove('active');
      expect(CareService.reminderFromRow(bare)!.schedule.active, isTrue);
    });

    test('a stopped reminder stays stopped', () {
      expect(CareService.reminderFromRow(row(active: false))!.schedule.active,
          isFalse);
    });

    test('never claims a caregiver-read row is pending local sync', () {
      final r = CareService.reminderFromRow(row())!;
      expect(r.schedule.pendingSync, isFalse);
      expect(r.medicine.pendingSync, isFalse);
      expect(r.schedule.deleted, isFalse);
    });
  });
}
