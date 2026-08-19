import 'package:dosely/data/local/database.dart';
import 'package:dosely/data/local/tables.dart';
import 'package:dosely/data/remote/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which dose logs a caregiver is told about.
///
/// The failure this pins down is not a crash. Announcing a `taken` log would
/// ring a phone in another city to report that someone *did* take their tablet
/// — at whatever hour they took it — which is the fastest way to teach a family
/// to mute the app that is supposed to be watching for them.
void main() {
  DoseLog log(String id, DoseAction action) => DoseLog(
        id: id,
        scheduleId: 'schedule-1',
        scheduledAt: DateTime.utc(2026, 8, 19, 9, 0),
        action: action.name,
        loggedAt: DateTime.utc(2026, 8, 19, 9, 30),
        source: 'auto',
        pendingSync: true,
      );

  group('missedDoseIdsIn', () {
    test('announces a missed dose', () {
      expect(
        SyncService.missedDoseIdsIn([log('a', DoseAction.missed)]),
        ['a'],
      );
    });

    test('says nothing about a dose that was taken', () {
      expect(SyncService.missedDoseIdsIn([log('a', DoseAction.taken)]), isEmpty);
    });

    test('says nothing about a dose that was snoozed', () {
      // A snooze is someone answering the alarm. They have been reminded and
      // said "not yet", which is not an incident.
      expect(SyncService.missedDoseIdsIn([log('a', DoseAction.snoozed)]), isEmpty);
    });

    test('picks the missed ones out of a mixed batch, in order', () {
      final ids = SyncService.missedDoseIdsIn([
        log('taken-1', DoseAction.taken),
        log('missed-1', DoseAction.missed),
        log('snoozed-1', DoseAction.snoozed),
        log('missed-2', DoseAction.missed),
      ]);

      expect(ids, ['missed-1', 'missed-2']);
    });

    test('says nothing about an empty batch', () {
      // The notifier short-circuits on an empty list rather than making a
      // round-trip to be told there is nothing to send.
      expect(SyncService.missedDoseIdsIn([]), isEmpty);
    });

    test('ignores an action it does not recognise', () {
      // A log written by a future build, pulled onto this one. Silence is the
      // right answer: we cannot say what it means, so we cannot say it was
      // missed.
      final unknown = DoseLog(
        id: 'a',
        scheduleId: 'schedule-1',
        scheduledAt: DateTime.utc(2026, 8, 19, 9, 0),
        action: 'refused',
        loggedAt: DateTime.utc(2026, 8, 19, 9, 30),
        source: 'auto',
        pendingSync: true,
      );

      expect(SyncService.missedDoseIdsIn([unknown]), isEmpty);
    });
  });
}
