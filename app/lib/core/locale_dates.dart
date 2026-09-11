/// Locale-aware weekday/month names and date ordering, shared by every
/// screen and export that used to hardcode English weekday/month arrays
/// (GitHub issue #100). Before this, a device set to a non-English locale —
/// or even just a non-US English locale, since date *order* differs between
/// e.g. en_US ("August 21, 2026") and en_GB ("21 August 2026") — still saw
/// hardcoded English, US-ordering-agnostic dates everywhere.
///
/// This module is intentionally about *formatting*, not translation: the
/// surrounding sentences ("Today", "Yesterday", "N minutes ago", "Mark
/// taken") stay English. Only the weekday/month names and their order,
/// which `intl`'s `DateFormat` already knows correctly per locale, change.
library;

import 'dart:io';

import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

bool _dateSymbolsInitialized = false;

/// `intl` ships symbol/pattern data for every locale in the package itself
/// (no asset loading), but that data has to be registered once before any
/// non-English `DateFormat` is built or it throws. Doing this lazily, on
/// first use, means a test or screen that never formats a date pays
/// nothing and never needs its own `main()`/binding setup for this.
void _ensureDateSymbolsInitialized() {
  if (_dateSymbolsInitialized) return;
  _dateSymbolsInitialized = true;
  // Synchronous under the hood (it only populates in-memory maps), so
  // callers below can use a `DateFormat` immediately without awaiting this.
  initializeDateFormatting();
}

/// The locale `DateFormat` should use. Prefers [Intl.defaultLocale] — unset
/// in the running app, but tests can pin it (see `dose_calendar_test.dart`)
/// to keep an assertion on formatted text deterministic across machines —
/// falling back to the device's own locale via `dart:io`'s `Platform`, the
/// same source this codebase already reads platform info from elsewhere
/// (`auth_service.dart`, `push_service.dart`, `notification_service.dart`).
/// There is no `BuildContext`-based alternative here: this app does not
/// register `flutter_localizations` delegates or `supportedLocales` on
/// `MaterialApp` (see `main.dart`), so `Localizations.localeOf(context)`
/// would always resolve to a single fixed default rather than the device's
/// actual locale.
String currentLocaleName() {
  final pinned = Intl.defaultLocale;
  if (pinned != null) return pinned;
  try {
    return Platform.localeName;
  } catch (_) {
    return 'en_US';
  }
}

/// Builds a [DateFormat] for the given ICU skeleton (e.g. `'EEEE'`,
/// `'yMMMMd'`) in [currentLocaleName], falling back to `en_US` if the
/// device reports a locale string `intl` doesn't recognise at all — a
/// screen must still show *a* correctly-shaped date rather than crash.
DateFormat _localeFormat(String skeleton) {
  _ensureDateSymbolsInitialized();
  final locale = currentLocaleName();
  try {
    return DateFormat(skeleton, locale);
  } on ArgumentError {
    return DateFormat(skeleton, 'en_US');
  }
}

/// Full weekday name in the device's locale, e.g. "Tuesday".
String localeWeekdayName(DateTime date) => _localeFormat('EEEE').format(date);

/// Abbreviated weekday name in the device's locale, e.g. "Tue".
String localeWeekdayAbbr(DateTime date) => _localeFormat('E').format(date);

/// Month + year, locale-ordered, e.g. "August 2026".
String localeMonthYear(DateTime date) => _localeFormat('yMMMM').format(date);

/// Day + full month name, locale-ordered, no year, e.g. "21 August" (en_GB)
/// or "August 21" (en_US).
String localeDayMonth(DateTime date) => _localeFormat('MMMMd').format(date);

/// Day + abbreviated month name, locale-ordered, no year, e.g. "21 Aug"
/// (en_GB) or "Aug 21" (en_US).
String localeDayMonthAbbr(DateTime date) => _localeFormat('MMMd').format(date);

/// Day + full month + year, locale-ordered, e.g. "21 August 2026" (en_GB)
/// or "August 21, 2026" (en_US).
String localeDayMonthYear(DateTime date) =>
    _localeFormat('yMMMMd').format(date);

/// Day + abbreviated month + year, locale-ordered, e.g. "21 Aug 2026"
/// (en_GB) or "Aug 21, 2026" (en_US).
String localeShortDate(DateTime date) => _localeFormat('yMMMd').format(date);

/// Sunday-first, CLDR "narrow" weekday letters (typically one glyph per
/// day) for a compact calendar header row — index 0 is Sunday, matching
/// this app's own `daysOfWeek` storage convention (see `dose_calendar.dart`
/// and `expected_doses.dart`).
List<String> localeNarrowWeekdays() {
  _ensureDateSymbolsInitialized();
  final locale = currentLocaleName();
  try {
    return DateFormat.EEEE(locale).dateSymbols.NARROWWEEKDAYS;
  } on ArgumentError {
    return DateFormat.EEEE('en_US').dateSymbols.NARROWWEEKDAYS;
  }
}

/// Locale-correct abbreviated weekday name for a day-of-week index stored
/// the way this app stores `daysOfWeek` — 0 = Sunday .. 6 = Saturday —
/// rather than for an actual calendar date.
String localeShortWeekdayForSundayIndex(int sundayIndexedDay) {
  _ensureDateSymbolsInitialized();
  final locale = currentLocaleName();
  try {
    return DateFormat.EEEE(locale).dateSymbols.SHORTWEEKDAYS[sundayIndexedDay];
  } on ArgumentError {
    return DateFormat.EEEE(
      'en_US',
    ).dateSymbols.SHORTWEEKDAYS[sundayIndexedDay];
  }
}
