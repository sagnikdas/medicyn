import 'package:dosely/features/care/care_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The feed is what a worried person in another city reads instead of
/// ringing to ask, so both halves of it are worth pinning: that a row from
/// PostgREST's nested shape is unpacked correctly, and that punctuality says
/// something true.
void main() {
  Map<String, dynamic> row({
    String action = 'taken',
    required String scheduledAt,
    required String loggedAt,
    String drugName = 'Metformin',
    String strength = '500mg',
    String doseAmount = '1 tablet',
  }) =>
      {
        'id': 'log-1',
        'scheduled_at': scheduledAt,
        'logged_at': loggedAt,
        'action': action,
        'source': 'notification',
        // PostgREST nests embedded resources one level per hop.
        'schedules': {
          'medicines': {
            'drug_name': drugName,
            'strength': strength,
            'dose_amount': doseAmount,
          },
        },
      };

  DoseEvent event({
    String action = 'taken',
    Duration lateBy = Duration.zero,
  }) {
    final due = DateTime.utc(2026, 8, 18, 8, 0);
    return DoseEvent.fromRow(row(
      action: action,
      scheduledAt: due.toIso8601String(),
      loggedAt: due.add(lateBy).toIso8601String(),
    ));
  }

  group('fromRow', () {
    test('unpacks the nested medicine', () {
      final e = event();

      expect(e.id, 'log-1');
      expect(e.drugName, 'Metformin');
      expect(e.strength, '500mg');
      expect(e.doseAmount, '1 tablet');
      expect(e.title, 'Metformin 500mg');
    });

    test('drops the strength from the title when there is none', () {
      final e = DoseEvent.fromRow(row(
        strength: '',
        scheduledAt: '2026-08-18T08:00:00.000Z',
        loggedAt: '2026-08-18T08:00:00.000Z',
      ));

      expect(e.title, 'Metformin');
    });

    test('survives a response missing its embedded rows', () {
      // Should never happen — the query inner-joins both — but a screen full
      // of medicines is worth more than a crash if the shape ever changes.
      final e = DoseEvent.fromRow({
        'id': 'log-2',
        'scheduled_at': '2026-08-18T08:00:00.000Z',
        'logged_at': '2026-08-18T08:00:00.000Z',
        'action': 'taken',
      });

      expect(e.drugName, 'Medicine');
      expect(e.strength, isEmpty);
    });
  });

  group('punctuality', () {
    test('treats a few minutes either way as on time', () {
      expect(event(lateBy: Duration.zero).punctuality, 'On time');
      expect(event(lateBy: const Duration(minutes: 4)).punctuality, 'On time');
      expect(event(lateBy: const Duration(minutes: -4)).punctuality, 'On time');
    });

    test('reports minutes, hours and days in the right units', () {
      expect(event(lateBy: const Duration(minutes: 12)).punctuality, '12 minutes late');
      expect(event(lateBy: const Duration(hours: 1)).punctuality, '1 hour late');
      expect(event(lateBy: const Duration(hours: 3)).punctuality, '3 hours late');
      expect(event(lateBy: const Duration(days: 1)).punctuality, '1 day late');
      expect(event(lateBy: const Duration(days: 2)).punctuality, '2 days late');
    });

    test('reports early doses as early, not as negative lateness', () {
      expect(event(lateBy: const Duration(minutes: -30)).punctuality, '30 minutes early');
    });

    test('says nothing for a dose that was never taken', () {
      // "Snoozed, 2 hours late" would be nonsense — it was not taken at all.
      expect(event(action: 'snoozed', lateBy: const Duration(hours: 2)).punctuality, isNull);
      expect(event(action: 'missed', lateBy: const Duration(hours: 2)).punctuality, isNull);
    });
  });

  group('lateness', () {
    test('is the gap between due and answered, regardless of timezone', () {
      // Both timestamps are absolute instants, which is exactly why the feed
      // leads with this rather than a clock time.
      final e = DoseEvent.fromRow(row(
        scheduledAt: '2026-08-18T02:30:00.000Z',
        loggedAt: '2026-08-18T02:45:00.000Z',
      ));

      expect(e.lateness, const Duration(minutes: 15));
    });
  });
}
