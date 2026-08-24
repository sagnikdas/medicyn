import 'package:dosely/data/local/database.dart';
import 'package:dosely/data/local/tables.dart';
import 'package:dosely/features/notification_engine/missed_doses.dart';
import 'package:dosely/features/notification_engine/notification_actions.dart';
import 'package:dosely/features/notification_engine/notification_ids.dart';
import 'package:dosely/features/notification_engine/notification_service.dart';
import 'package:dosely/features/notification_engine/schedule_validation.dart';
import 'package:dosely/features/reminders_home/refill.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Snoozing is the interaction most likely to be repeated — the alarm loops
/// until it is answered, and the person answering it is often half awake.
/// Each press used to write a history row and arm another alarm, and the
/// next foreground threw the one real alarm away.
void main() {
  const scheduleId = '0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0';
  const medicineId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  final due = DateTime(2026, 8, 21, 8);

  group('dose log ids', () {
    test('a repeated answer is the same row, not another one', () {
      expect(
        doseLogIdFor(scheduleId, due, DoseAction.snoozed),
        doseLogIdFor(scheduleId, due, DoseAction.snoozed),
      );
    });

    test('snoozing then taking stays two facts about the dose', () {
      expect(
        doseLogIdFor(scheduleId, due, DoseAction.snoozed),
        isNot(doseLogIdFor(scheduleId, due, DoseAction.taken)),
      );
    });

    test('two occurrences of the same reminder do not share a row', () {
      expect(
        doseLogIdFor(scheduleId, due, DoseAction.taken),
        isNot(doseLogIdFor(
            scheduleId, due.add(const Duration(hours: 12)), DoseAction.taken)),
      );
    });

    test('the id is a uuid Postgres will accept', () {
      expect(
        doseLogIdFor(scheduleId, due, DoseAction.taken),
        matches(RegExp(r'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$')),
      );
    });

    test('a schedule id that is not a uuid still records the dose', () {
      final a = doseLogIdFor('not-a-uuid', due, DoseAction.taken);
      final b = doseLogIdFor('not-a-uuid', due, DoseAction.taken);
      expect(a, isNotEmpty);
      expect(a, isNot(b), reason: 'falls back to a random id rather than none');
    });

    test('missedDoseId is unchanged, because two devices agree on it', () {
      // Missed rows are de-duplicated across devices and on the server by
      // this id. Folding the action into the hash — as doseLogIdFor does —
      // would silently double every missed dose during a rollout.
      expect(
        missedDoseId(scheduleId, DateTime.utc(2026, 8, 21, 8)),
        '0f1e2d3c-4b5a-6978-8796-a5b4c4af3b00',
      );
      expect(
        missedDoseId(scheduleId, due),
        isNot(doseLogIdFor(scheduleId, due, DoseAction.missed)),
      );
    });
  });

  group('snooze notification id', () {
    test('pressing snooze again replaces the alarm rather than adding one', () {
      expect(
        snoozeNotificationId(scheduleId, due),
        snoozeNotificationId(scheduleId, due),
      );
    });

    test('a different dose gets its own re-reminder', () {
      expect(
        snoozeNotificationId(scheduleId, due),
        isNot(snoozeNotificationId(
            scheduleId, due.add(const Duration(hours: 12)))),
      );
    });

    test('never collides with a slot in the recurring series', () {
      final snooze = snoozeNotificationId(scheduleId, due);
      for (final slot in ['08:00', '1-08:00', 'slot-0', 'slot-7', 'due-08:00']) {
        expect(notificationIdFor(scheduleId, slot), isNot(snooze),
            reason: slot);
      }
    });

    test('fits the positive int range Android requires', () {
      final id = snoozeNotificationId(scheduleId, due);
      expect(id, greaterThan(0));
      expect(id, lessThanOrEqualTo(0x7fffffff));
    });
  });

  group('recording an answer', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await db.upsertMedicine(MedicinesCompanion.insert(
        id: medicineId,
        drugName: 'Metformin',
        tabletsRemaining: const Value(30),
        tabletsPerDose: const Value(1),
        // Safely before `due` (and before whenever this test actually
        // runs), so takenCountSince's strict-greater-than comparison can
        // never tie with a dose logged moments after setUp.
        updatedAt: Value(DateTime(2020, 1, 1)),
      ));
      await db.upsertSchedule(SchedulesCompanion.insert(
        id: scheduleId,
        medicineId: medicineId,
        frequencyType: 'daily',
        times: const <String>['08:00'],
        daysOfWeek: const Value(<int>[]),
      ));
    });
    tearDown(() => db.close());

    Future<List<DoseLog>> logs() => db.watchDoseLogsForSchedule(scheduleId).first;

    // The bottle count is no longer decremented in place — it's derived from
    // doses taken since the medicine's baseline (see derivedTabletsRemaining)
    // — so these read the same way the app itself would show the count.
    Future<int?> remaining() async {
      final medicine = (await db.medicineById(medicineId))!;
      final taken = await db.takenCountSince(scheduleId, medicine.updatedAt);
      return derivedTabletsRemaining(medicine, taken);
    }

    test('five taps of Taken are one dose and one tablet', () async {
      for (var i = 0; i < 5; i++) {
        await recordDoseTaken(db, scheduleId: scheduleId, scheduledAt: due);
      }

      expect(await logs(), hasLength(1));
      expect(await remaining(), 29,
          reason: 'the bottle must not empty faster than it is emptied');
    });

    test('taking two different doses takes two tablets', () async {
      await recordDoseTaken(db, scheduleId: scheduleId, scheduledAt: due);
      await recordDoseTaken(
          db, scheduleId: scheduleId, scheduledAt: due.add(const Duration(hours: 12)));

      expect(await logs(), hasLength(2));
      expect(await remaining(), 28);
    });

    test('a snooze after a taken is still recorded as its own fact', () async {
      await recordDoseTaken(db, scheduleId: scheduleId, scheduledAt: due);
      await db.recordDoseAction(
        id: doseLogIdFor(scheduleId, due, DoseAction.snoozed),
        scheduleId: scheduleId,
        scheduledAt: due,
        action: DoseAction.snoozed,
      );

      final all = await logs();
      expect(all, hasLength(2));
      expect(all.map((l) => l.action).toSet(), {'taken', 'snoozed'});
    });

    test('every answer is attributed to the dose, not to the tap', () async {
      await recordDoseTaken(db, scheduleId: scheduleId, scheduledAt: due);
      expect((await logs()).single.scheduledAt, due);
    });
  });

  group('a snooze does not settle the dose', () {
    late AppDatabase db;
    final defined = DateTime(2026, 8, 1);

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await db.upsertMedicine(
          MedicinesCompanion.insert(id: medicineId, drugName: 'Metformin'));
      await db.upsertSchedule(SchedulesCompanion.insert(
        id: scheduleId,
        medicineId: medicineId,
        frequencyType: 'daily',
        times: const <String>['08:00'],
        daysOfWeek: const Value(<int>[]),
        updatedAt: Value(defined),
      ));
    });
    tearDown(() => db.close());

    Future<void> snoozeAt(DateTime at) => db.recordDoseAction(
          id: doseLogIdFor(scheduleId, due, DoseAction.snoozed),
          scheduleId: scheduleId,
          scheduledAt: due,
          action: DoseAction.snoozed,
          loggedAt: at,
        );

    test('snoozing and then ignoring it is reported missed', () async {
      // The strongest signal a dose is about to be forgotten used to be the
      // one thing that guaranteed nobody was told about it.
      await snoozeAt(due.add(const Duration(minutes: 2)));

      final written = await const MissedDoseDetector()
          .sweep(db, now: due.add(const Duration(hours: 2)), lookback: const Duration(hours: 3));

      expect(written, 1);
    });

    test('a snooze still running keeps the sweep quiet', () async {
      await snoozeAt(due.add(const Duration(minutes: 2)));

      // Five minutes after the snooze: the re-reminder has not fired yet.
      final written = await const MissedDoseDetector()
          .sweep(db, now: due.add(const Duration(minutes: 7)), lookback: const Duration(hours: 3));

      expect(written, 0);
    });

    test('taking the dose still settles it', () async {
      await db.recordDoseAction(
        id: doseLogIdFor(scheduleId, due, DoseAction.taken),
        scheduleId: scheduleId,
        scheduledAt: due,
        action: DoseAction.taken,
        loggedAt: due.add(const Duration(minutes: 2)),
      );

      final written = await const MissedDoseDetector()
          .sweep(db, now: due.add(const Duration(hours: 2)), lookback: const Duration(hours: 3));

      expect(written, 0);
    });
  });

  group('nextWallClockDay', () {
    setUpAll(tzdata.initializeTimeZones);

    const ClockTime eight = (hour: 8, minute: 0);

    test('keeps the clock time across the spring forward', () {
      final ny = tz.getLocation('America/New_York');
      tz.setLocalLocation(ny);
      final next = nextWallClockDay(tz.TZDateTime(ny, 2026, 3, 7, 8), eight);
      expect(next.year, 2026);
      expect(next.month, 3);
      expect(next.day, 8);
      expect(next.hour, 8, reason: 'adding 24h would have armed this for 09:00');
    });

    test('keeps the clock time across the fall back', () {
      final ny = tz.getLocation('America/New_York');
      tz.setLocalLocation(ny);
      final next = nextWallClockDay(tz.TZDateTime(ny, 2026, 10, 31, 8), eight);
      expect(next.day, 1);
      expect(next.month, 11);
      expect(next.hour, 8, reason: 'adding 24h would have armed this for 07:00');
    });

    test('rolls the month and the year over', () {
      final utc = tz.getLocation('Etc/UTC');
      tz.setLocalLocation(utc);
      expect(nextWallClockDay(tz.TZDateTime(utc, 2026, 12, 31, 8), eight).year, 2027);
      expect(nextWallClockDay(tz.TZDateTime(utc, 2026, 1, 31, 8), eight).month, 2);
    });

    test('an ordinary day is simply the next one, same time', () {
      final utc = tz.getLocation('Etc/UTC');
      tz.setLocalLocation(utc);
      final next = nextWallClockDay(tz.TZDateTime(utc, 2026, 6, 1, 8), eight);
      expect(next, tz.TZDateTime(utc, 2026, 6, 2, 8));
    });
  });
}
