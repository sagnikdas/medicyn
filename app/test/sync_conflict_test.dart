import 'package:dosely/data/remote/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The rule that decides which copy of a reminder survives when two devices
/// have both edited it. Worth testing on its own: it is a three-line function
/// whose failure mode is a dose quietly reverting to a value someone
/// deliberately changed, with nothing on screen to say it happened.
void main() {
  final earlier = DateTime.utc(2026, 8, 18, 9, 0);
  final later = DateTime.utc(2026, 8, 18, 11, 0);

  group('remoteWins', () {
    test('takes a row this device has never seen', () {
      expect(SyncService.remoteWins(null, earlier), isTrue);
    });

    test('takes a strictly newer remote edit', () {
      expect(SyncService.remoteWins(earlier, later), isTrue);
    });

    test('keeps the local copy when the remote one is older', () {
      expect(SyncService.remoteWins(later, earlier), isFalse);
    });

    test('keeps the local copy when the timestamps match', () {
      // Equal means same version. Rewriting the row would wake every
      // .watch() stream in the app for no change at all.
      expect(SyncService.remoteWins(earlier, earlier), isFalse);
    });

    test('resolves sub-second differences rather than rounding them away', () {
      final a = DateTime.utc(2026, 8, 18, 9, 0, 0, 100);
      final b = DateTime.utc(2026, 8, 18, 9, 0, 0, 200);
      expect(SyncService.remoteWins(a, b), isTrue);
      expect(SyncService.remoteWins(b, a), isFalse);
    });
  });

  group('remoteUpdatedAt', () {
    test('reads the timestamp the server sent', () {
      final row = <String, dynamic>{'updated_at': '2026-08-18T11:00:00.000Z'};
      expect(SyncService.remoteUpdatedAt(row), equals(later));
    });

    test('treats a missing timestamp as the beginning of time', () {
      // A row written before versioning existed. It must not be able to
      // masquerade as new and overwrite a real local edit.
      final row = <String, dynamic>{'id': 'abc'};
      final resolved = SyncService.remoteUpdatedAt(row);

      expect(resolved.millisecondsSinceEpoch, equals(0));
      expect(SyncService.remoteWins(earlier, resolved), isFalse);
    });

    test('an unversioned remote row still lands on a device without it', () {
      // The epoch fallback must not stop a fresh install from restoring
      // rows that predate versioning — "never seen it" outranks the clock.
      final row = <String, dynamic>{'id': 'abc'};
      expect(SyncService.remoteWins(null, SyncService.remoteUpdatedAt(row)), isTrue);
    });
  });
}
