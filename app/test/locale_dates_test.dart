import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:medicyn/core/locale_dates.dart';

/// Coverage for GitHub issue #100: weekday/month names and date order used
/// to be hardcoded English arrays everywhere (see the call sites this
/// module replaced -- `edit_attribution.dart`, `dose_calendar.dart`,
/// `day_dose_list.dart`, `reminder_copy.dart`, `medicine_fields_form.dart`,
/// `android_today_screen.dart`, `emergency_card_screen.dart`, and the two
/// PDF exports). These tests pin [Intl.defaultLocale] rather than relying
/// on the host machine's own locale, the same way the rest of this app
/// injects a fake `now` instead of depending on the real clock.
void main() {
  tearDown(() => Intl.defaultLocale = null);

  group('currentLocaleName', () {
    test('honours a pinned Intl.defaultLocale over the platform locale', () {
      Intl.defaultLocale = 'fr_FR';
      expect(currentLocaleName(), 'fr_FR');
    });
  });

  group('localeWeekdayName', () {
    final tuesday = DateTime(2026, 8, 18);

    test('is English by default', () {
      Intl.defaultLocale = 'en_US';
      expect(localeWeekdayName(tuesday), 'Tuesday');
    });

    test('is translated for a non-English locale', () {
      Intl.defaultLocale = 'fr_FR';
      expect(localeWeekdayName(tuesday), 'mardi');
    });
  });

  group('localeWeekdayAbbr', () {
    test('abbreviates in the given locale', () {
      Intl.defaultLocale = 'en_US';
      expect(localeWeekdayAbbr(DateTime(2026, 8, 21)), 'Fri');
    });
  });

  group('date order follows locale, not just the language', () {
    final date = DateTime(2026, 8, 21);

    test('en_US puts the month before the day', () {
      Intl.defaultLocale = 'en_US';
      expect(localeDayMonthYear(date), 'August 21, 2026');
      expect(localeDayMonth(date), 'August 21');
      expect(localeShortDate(date), 'Aug 21, 2026');
    });

    test('en_GB puts the day before the month -- same language, same date, '
        'different order', () {
      Intl.defaultLocale = 'en_GB';
      expect(localeDayMonthYear(date), '21 August 2026');
      expect(localeDayMonth(date), '21 August');
      expect(localeShortDate(date), '21 Aug 2026');
    });
  });

  group('localeMonthYear', () {
    test('formats month and year', () {
      Intl.defaultLocale = 'en_US';
      expect(localeMonthYear(DateTime(2026, 8, 21)), 'August 2026');
    });
  });

  group('localeShortWeekdayForSundayIndex', () {
    test('index 0 is Sunday, matching this app\'s daysOfWeek storage', () {
      Intl.defaultLocale = 'en_US';
      expect(localeShortWeekdayForSundayIndex(0), 'Sun');
      expect(localeShortWeekdayForSundayIndex(1), 'Mon');
      expect(localeShortWeekdayForSundayIndex(6), 'Sat');
    });
  });

  group('localeNarrowWeekdays', () {
    test('returns seven letters, Sunday first', () {
      Intl.defaultLocale = 'en_US';
      final letters = localeNarrowWeekdays();
      expect(letters, hasLength(7));
      expect(letters.first, 'S'); // Sunday
    });
  });

  group('an unrecognised locale string', () {
    test('falls back to English instead of throwing', () {
      Intl.defaultLocale = 'not-a-real-locale';
      expect(
        () => localeWeekdayName(DateTime(2026, 8, 18)),
        returnsNormally,
      );
      expect(localeWeekdayName(DateTime(2026, 8, 18)), 'Tuesday');
    });
  });
}
