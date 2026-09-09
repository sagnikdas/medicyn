import 'package:medicyn/features/review_prescription/care_recurrence.dart';
import 'package:medicyn/features/review_prescription/parsed_care_item.dart';
import 'package:flutter_test/flutter_test.dart';

/// The date math that turns "physiotherapy, weekly, 6 sessions" into 6
/// concrete reminder dates -- this is where the "generate individual
/// reminders now, no recurring-series schema" decision is actually
/// implemented, so it is covered independently of the review screen that
/// calls it.
void main() {
  group('expandCareOccurrences', () {
    test('none always returns exactly one date, at firstDate', () {
      final item = ParsedCareItem(
        firstDate: DateTime(2026, 10, 1),
        recurrence: CareRecurrence.none,
        occurrenceCount: 1,
      );
      expect(expandCareOccurrences(item), [DateTime(2026, 10, 1)]);
    });

    test('none ignores a bogus occurrenceCount rather than repeating the date', () {
      // Malformed server data (recurrence none but occurrenceCount > 1)
      // must not produce several identical reminders.
      final item = ParsedCareItem(
        firstDate: DateTime(2026, 10, 1),
        recurrence: CareRecurrence.none,
        occurrenceCount: 6,
      );
      expect(expandCareOccurrences(item), [DateTime(2026, 10, 1)]);
    });

    test('weekly steps 7 days apart for the full occurrence count', () {
      final item = ParsedCareItem(
        title: 'Physiotherapy',
        firstDate: DateTime(2026, 9, 17),
        recurrence: CareRecurrence.weekly,
        occurrenceCount: 6,
      );
      expect(expandCareOccurrences(item), [
        DateTime(2026, 9, 17),
        DateTime(2026, 9, 24),
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 8),
        DateTime(2026, 10, 15),
        DateTime(2026, 10, 22),
      ]);
    });

    test('everyNDays steps intervalN days apart', () {
      final item = ParsedCareItem(
        firstDate: DateTime(2026, 1, 1),
        recurrence: CareRecurrence.everyNDays,
        intervalN: 10,
        occurrenceCount: 3,
      );
      expect(expandCareOccurrences(item), [
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 11),
        DateTime(2026, 1, 21),
      ]);
    });

    test('everyNMonths steps intervalN months apart', () {
      final item = ParsedCareItem(
        firstDate: DateTime(2026, 1, 15),
        recurrence: CareRecurrence.everyNMonths,
        intervalN: 3,
        occurrenceCount: 4,
      );
      expect(expandCareOccurrences(item), [
        DateTime(2026, 1, 15),
        DateTime(2026, 4, 15),
        DateTime(2026, 7, 15),
        DateTime(2026, 10, 15),
      ]);
    });

    test('everyNMonths clamps the day rather than overflowing into the next month', () {
      // 31 Jan + 1 month must land on 28 Feb (2026 is not a leap year), not
      // roll over to 3 Mar the way DateTime(2026, 2, 31) would.
      final item = ParsedCareItem(
        firstDate: DateTime(2026, 1, 31),
        recurrence: CareRecurrence.everyNMonths,
        intervalN: 1,
        occurrenceCount: 3,
      );
      expect(expandCareOccurrences(item), [
        DateTime(2026, 1, 31),
        DateTime(2026, 2, 28),
        // The third step is 1 month after the *original* 31 Jan, not after
        // the clamped 28 Feb -- April has 30 days, so 31 Mar clamps to 30.
        DateTime(2026, 3, 31),
      ]);
    });

    test('everyNMonths handles a leap-year February', () {
      final item = ParsedCareItem(
        firstDate: DateTime(2024, 1, 31),
        recurrence: CareRecurrence.everyNMonths,
        intervalN: 1,
        occurrenceCount: 2,
      );
      expect(expandCareOccurrences(item), [
        DateTime(2024, 1, 31),
        DateTime(2024, 2, 29), // 2024 is a leap year
      ]);
    });

    test('a null firstDate falls back to the given now', () {
      final item = ParsedCareItem(
        recurrence: CareRecurrence.none,
        occurrenceCount: 1,
      );
      final dates = expandCareOccurrences(item, now: DateTime(2026, 6, 15, 9, 30));
      // Normalized to a calendar day, not carrying the time-of-day through.
      expect(dates, [DateTime(2026, 6, 15)]);
    });

    test('occurrenceCount above the schema cap is clamped rather than trusted', () {
      final item = ParsedCareItem(
        firstDate: DateTime(2026, 1, 1),
        recurrence: CareRecurrence.weekly,
        occurrenceCount: 999,
      );
      expect(expandCareOccurrences(item).length, 52);
    });

    test('intervalN of zero is clamped to at least 1, not a zero-length step', () {
      final item = ParsedCareItem(
        firstDate: DateTime(2026, 1, 1),
        recurrence: CareRecurrence.everyNDays,
        intervalN: 0,
        occurrenceCount: 3,
      );
      expect(expandCareOccurrences(item), [
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 2),
        DateTime(2026, 1, 3),
      ]);
    });
  });
}
