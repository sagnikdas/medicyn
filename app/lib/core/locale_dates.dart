/// Locale-aware weekday/month names, date ordering, and relative-time
/// ("N minutes/hours/days ago") pluralization, shared by every screen and
/// export that used to hardcode English weekday/month arrays or English
/// plural rules (GitHub issue #100). Before this, a device set to a
/// non-English locale — or even just a non-US English locale, since date
/// *order* differs between e.g. en_US ("August 21, 2026") and en_GB
/// ("21 August 2026") — still saw hardcoded English, US-ordering-agnostic
/// dates everywhere, and relative-time strings like "sync status" always
/// said "3h ago" with no locale-correct pluralization or digit rendering.
///
/// This module is intentionally about *formatting*, not full translation:
/// the English words themselves ("Today", "minute", "hour", "day", "ago")
/// are not translated into other languages here — doing that for real
/// would mean translating every user-facing string in the app, which needs
/// Flutter's ARB-based `flutter gen-l10n` pipeline (`AppLocalizations`,
/// `.arb` files, `flutter_localizations`), none of which this app has set
/// up (see `main.dart`). That is a separate, much larger infrastructure
/// task, tracked as remaining scope on issue #100 rather than something
/// bolted on ad hoc here.
///
/// What *is* genuinely locale-aware in this module, including for
/// relative-time phrasing:
///  - weekday/month names and their order (`DateFormat`), and
///  - plural *category* selection for a count (`Intl.plural`) — e.g.
///    Arabic has six plural categories (zero/one/two/few/many/other)
///    where English only really uses two (one/other), and `Intl.plural`
///    picks the CLDR-correct category for the running locale rather than
///    a hardcoded `count == 1` check, and
///  - the numeral itself (`NumberFormat`) — e.g. locales that render
///    digits in a non-Latin script.
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

/// Renders [count] using [locale]'s own numeral system and grouping (e.g.
/// Eastern Arabic digits in `ar`), falling back to plain `en_US` digits if
/// the locale string isn't one `NumberFormat` recognises.
///
/// Unlike `DateFormat`'s month/weekday symbols, `NumberFormat`'s per-locale
/// symbol tables are compiled into the package itself and need no
/// `initializeDateFormatting()`-style call before use.
String _localeNumber(int count, String locale) {
  try {
    return NumberFormat.decimalPattern(locale).format(count);
  } on ArgumentError {
    return NumberFormat.decimalPattern('en_US').format(count);
  }
}

/// One locale-correct plural form of an English count phrase, e.g.
/// `_agoUnit(1, locale, one: 'minute', other: 'minutes')` -> "1 minute" and
/// `_agoUnit(5, locale, one: 'minute', other: 'minutes')` -> "5 minutes".
///
/// The English words `one`/`other` themselves are not translated (see the
/// library doc comment for why), but which of them is chosen is decided by
/// `Intl.plural`'s CLDR plural-category logic for [locale] rather than a
/// hardcoded `count == 1` check, and the numeral is rendered through
/// [_localeNumber]. For a locale whose plural rules distinguish more than
/// English's one/other (e.g. Arabic's zero/one/two/few/many/other), the
/// extra categories fall back to `other` here since no translated word
/// exists for them yet — a real gap, called out in the module doc comment,
/// that only full translation infrastructure can close.
String _agoUnit(
  int count,
  String locale, {
  required String one,
  required String other,
}) {
  final word = Intl.plural(
    count,
    one: one,
    other: other,
    locale: locale,
  );
  return '${_localeNumber(count, locale)} $word';
}

/// Locale-aware "N minutes/hours/days ago" relative-time phrasing for a
/// past [value], replacing the hardcoded, unpluralized `'${n}m ago'` /
/// `'${n}h ago'` / `'${n}d ago'` strings this app used to build directly
/// (see `sync_status.dart`'s `_formatAge`, GitHub issue #100).
///
/// [now] lets callers (and tests) pin the reference time instead of
/// depending on the real clock, the same pattern used elsewhere in this
/// app. The unit words ("minute", "hour", "day", "ago") stay English — see
/// the library doc comment for exactly why — but the plural form of each
/// word and the numeral itself are chosen correctly for [currentLocaleName].
String localeRelativeAge(DateTime value, {DateTime? now}) {
  final locale = currentLocaleName();
  final age = (now ?? DateTime.now()).difference(value);
  if (age.inMinutes < 1) return 'just now';
  if (age.inHours < 1) {
    return '${_agoUnit(age.inMinutes, locale, one: 'minute', other: 'minutes')} ago';
  }
  if (age.inDays < 1) {
    return '${_agoUnit(age.inHours, locale, one: 'hour', other: 'hours')} ago';
  }
  return '${_agoUnit(age.inDays, locale, one: 'day', other: 'days')} ago';
}
