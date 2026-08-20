import 'package:dosely/features/notification_engine/interval_dose_sequence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('intervalDoseSequence', () {
    test('walks a stable lattice from the origin, not from today', () {
      // Origin 8 Aug 08:00, 5-hour interval. A re-anchor-to-today algorithm
      // would name different slots on the 9th than on the 8th.
      final origin = DateTime(2026, 8, 8, 8, 0);
      final doses = intervalDoseSequence(
        origin: origin,
        intervalHours: 5,
        from: DateTime(2026, 8, 8, 15, 32),
        to: DateTime(2026, 8, 9, 12, 0),
      );

      expect(doses, [
        DateTime(2026, 8, 8, 18, 0),
        DateTime(2026, 8, 8, 23, 0),
        DateTime(2026, 8, 9, 4, 0),
        DateTime(2026, 8, 9, 9, 0),
      ]);
    });

    test('includes the start of a half-open window', () {
      expect(
        intervalDoseSequence(
          origin: DateTime(2026, 8, 8, 8, 0),
          intervalHours: 8,
          from: DateTime(2026, 8, 8, 8, 0),
          to: DateTime(2026, 8, 8, 16, 0),
        ),
        [DateTime(2026, 8, 8, 8, 0)],
      );
    });

    test('excludes the end of a half-open window', () {
      expect(
        intervalDoseSequence(
          origin: DateTime(2026, 8, 8, 8, 0),
          intervalHours: 8,
          from: DateTime(2026, 8, 8, 0, 0),
          to: DateTime(2026, 8, 8, 16, 0),
        ),
        [DateTime(2026, 8, 8, 8, 0)],
      );
    });

    test('arming uses an exclusive start so the due-now slot is not re-armed', () {
      expect(
        intervalDoseSequence(
          origin: DateTime(2026, 8, 8, 8, 0),
          intervalHours: 8,
          from: DateTime(2026, 8, 8, 16, 0),
          to: DateTime(2026, 8, 9, 0, 0),
          includeFrom: false,
        ),
        isEmpty,
      );
      expect(
        intervalDoseSequence(
          origin: DateTime(2026, 8, 8, 8, 0),
          intervalHours: 8,
          from: DateTime(2026, 8, 8, 16, 0),
          to: DateTime(2026, 8, 9, 8, 1),
          includeFrom: false,
        ),
        [DateTime(2026, 8, 9, 0, 0), DateTime(2026, 8, 9, 8, 0)],
      );
    });

    test('refuses a zero interval rather than looping', () {
      expect(
        intervalDoseSequence(
          origin: DateTime(2026, 8, 8, 8, 0),
          intervalHours: 0,
          from: DateTime(2026, 8, 8),
          to: DateTime(2026, 8, 9),
        ),
        isEmpty,
      );
    });
  });
}
