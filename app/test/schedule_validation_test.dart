import 'package:medicyn/data/local/tables.dart';
import 'package:medicyn/features/notification_engine/schedule_validation.dart';
import 'package:flutter_test/flutter_test.dart';

/// These cover the values that used to make the alarm scheduler loop forever.
///
/// The failure they guard against is not a crash: `reconcile` cancels every
/// alarm on the device before re-arming, so a schedule it cannot process left
/// the phone with no medication reminders at all, across restarts, with
/// nothing shown to the user.
void main() {
  group('parseClockTime', () {
    test('accepts an ordinary padded time', () {
      expect(parseClockTime('09:05'), (hour: 9, minute: 5));
      expect(parseClockTime('00:00'), (hour: 0, minute: 0));
      expect(parseClockTime('23:59'), (hour: 23, minute: 59));
    });

    test('accepts a single-digit hour, which names an unambiguous time', () {
      expect(parseClockTime('9:05'), (hour: 9, minute: 5));
    });

    test('rejects a non-numeric time instead of throwing', () {
      // Used to be int.parse, which threw FormatException and aborted the
      // caller mid-reconcile.
      expect(parseClockTime('9am'), isNull);
      expect(parseClockTime('morning'), isNull);
      expect(parseClockTime(''), isNull);
    });

    test('rejects a time with no colon instead of throwing RangeError', () {
      expect(parseClockTime('0900'), isNull);
    });

    test('rejects an out-of-range time rather than rolling it over', () {
      // DateTime would silently turn 29:00 into 05:00 the next day and arm
      // the alarm at a time the user never chose.
      expect(parseClockTime('29:00'), isNull);
      expect(parseClockTime('24:00'), isNull);
      expect(parseClockTime('12:60'), isNull);
      expect(parseClockTime('-1:00'), isNull);
      expect(parseClockTime('12:-5'), isNull);
    });

    test('rejects extra components', () {
      expect(parseClockTime('09:05:30'), isNull);
    });
  });

  group('schedulableTimes', () {
    test('keeps the good entries and drops the rest, preserving order', () {
      final result = schedulableTimes(['08:00', '9am', '20:30', '29:00']);
      expect(result.map((t) => t.label), ['08:00', '20:30']);
      expect(result.first.clock, (hour: 8, minute: 0));
    });

    test('deduplicates, so one time cannot silently shadow another id', () {
      expect(schedulableTimes(['08:00', '08:00']).length, 1);
    });

    test('carries the original label through for notification ids', () {
      // Recomputing "9:05" as "09:05" would change the id of an alarm that
      // is already armed, orphaning it.
      expect(schedulableTimes(['9:05']).single.label, '9:05');
    });

    test('returns empty rather than throwing when nothing parses', () {
      expect(schedulableTimes(['9am', 'noon']), isEmpty);
    });
  });

  group('schedulableDays', () {
    test('keeps 0..6, sorted and deduplicated', () {
      expect(schedulableDays([3, 0, 3, 6]), [0, 3, 6]);
    });

    test('drops a day no DateTime.weekday can equal', () {
      // The value that made _nextInstanceOfTime spin forever.
      expect(schedulableDays([9]), isEmpty);
      expect(schedulableDays([-1]), isEmpty);
      expect(schedulableDays([7]), isEmpty);
    });

    test('keeps the valid days when only some are bad', () {
      expect(schedulableDays([1, 9, 5]), [1, 5]);
    });
  });

  group('schedulableIntervalHours', () {
    test('passes a sane interval through', () {
      expect(schedulableIntervalHours(8), 8);
      expect(schedulableIntervalHours(1), 1);
      expect(schedulableIntervalHours(24), 24);
    });

    test('defaults when the field was never set', () {
      expect(schedulableIntervalHours(null), 8);
    });

    test('rejects zero rather than defaulting to it', () {
      // An increment of zero never advances the walk that finds the next
      // slot. Typing 0 into "Every how many hours?" was enough to reach
      // this, and it took every other medicine's alarms down with it.
      expect(schedulableIntervalHours(0), isNull);
    });

    test('rejects a negative or absurd interval', () {
      expect(schedulableIntervalHours(-4), isNull);
      expect(schedulableIntervalHours(999), isNull);
    });

    test('does not substitute a guess for a value someone entered', () {
      // Falling back to 8 here would arm alarms at times nobody asked for.
      expect(schedulableIntervalHours(0, fallback: 8), isNull);
    });
  });

  group('sanitiseScheduleFields', () {
    test('passes a healthy row through unchanged', () {
      final f = sanitiseScheduleFields(
        frequencyType: 'specificDays',
        times: ['08:00'],
        daysOfWeek: [1, 3],
        intervalHours: null,
      );
      expect(f, isNotNull);
      expect(f!.frequency, FrequencyType.specificDays);
      expect(f.times, ['08:00']);
      expect(f.daysOfWeek, [1, 3]);
      expect(f.changed, isFalse);
    });

    test('salvages what it can and says it changed something', () {
      final f = sanitiseScheduleFields(
        frequencyType: 'specificDays',
        times: ['08:00', '9am'],
        daysOfWeek: [1, 9],
        intervalHours: null,
      );
      expect(f!.times, ['08:00']);
      expect(f.daysOfWeek, [1]);
      expect(f.changed, isTrue);
    });

    test('rejects a row whose frequency names nothing', () {
      // There is no way to guess what the row meant, and byName would throw.
      expect(
        sanitiseScheduleFields(
          frequencyType: 'hourly',
          times: ['08:00'],
          daysOfWeek: const [],
          intervalHours: null,
        ),
        isNull,
      );
      expect(
        sanitiseScheduleFields(
          frequencyType: null,
          times: ['08:00'],
          daysOfWeek: const [],
          intervalHours: null,
        ),
        isNull,
      );
    });

    test('rejects an every-X-hours row with an unusable interval', () {
      // Substituting the 8-hour default would arm alarms at times nobody
      // chose, so the row is refused rather than guessed at.
      expect(
        sanitiseScheduleFields(
          frequencyType: 'everyXHours',
          times: ['08:00'],
          daysOfWeek: const [],
          intervalHours: 0,
        ),
        isNull,
      );
    });

    test('ignores a stray interval on a frequency that does not use one', () {
      // The column is unread for daily schedules, so an odd value there is
      // not worth refusing a working reminder over.
      final f = sanitiseScheduleFields(
        frequencyType: 'daily',
        times: ['08:00'],
        daysOfWeek: const [],
        intervalHours: 0,
      );
      expect(f, isNotNull);
      expect(f!.frequency, FrequencyType.daily);
    });
  });

  group('frequencyTypeFromName', () {
    test('resolves every name the database can hold', () {
      for (final f in FrequencyType.values) {
        expect(frequencyTypeFromName(f.name), f);
      }
    });

    test('returns null rather than throwing on anything else', () {
      // FrequencyType.values.byName throws, which is how an unrecognised
      // string could abort a caller mid-reconcile.
      expect(frequencyTypeFromName('hourly'), isNull);
      expect(frequencyTypeFromName(''), isNull);
      expect(frequencyTypeFromName(null), isNull);
    });
  });
}
