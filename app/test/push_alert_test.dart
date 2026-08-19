import 'package:dosely/data/local/database.dart';
import 'package:dosely/data/local/tables.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which dose logs a caregiver is told about.
///
/// Two failures live here and they are different in kind. Announcing a `taken`
/// log would ring a phone in another city to report that someone *did* take
/// their tablet — the fastest way to teach a family to mute the app that is
/// supposed to be watching. Failing to offer a genuinely missed dose is the
/// silence the whole feature exists to remove.
///
/// The second is why this asks the database rather than a sync call's result.
/// An upsert that commits server-side but whose response never arrives used to
/// leave the dose in Postgres and the alert lost for good, with nothing
/// anywhere to say so.
void main() {
  late AppDatabase db;

  final now = DateTime(2026, 8, 19, 12, 0);
  const scheduleId = '0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0';
  const medicineId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.upsertMedicine(
      MedicinesCompanion.insert(id: medicineId, drugName: 'Metformin'),
    );
    await db.upsertSchedule(SchedulesCompanion.insert(
      id: scheduleId,
      medicineId: medicineId,
      frequencyType: FrequencyType.daily.name,
      times: const ['08:00'],
    ));
  });

  tearDown(() async => db.close());

  Future<void> givenLog(
    String id, {
    required DoseAction action,
    required DateTime loggedAt,
    bool synced = true,
  }) async {
    await db.into(db.doseLogs).insert(DoseLogsCompanion.insert(
          id: id,
          scheduleId: scheduleId,
          scheduledAt: loggedAt,
          action: action.name,
          loggedAt: Value(loggedAt),
          pendingSync: Value(!synced),
        ));
  }

  Future<List<String>> announceable({Duration window = const Duration(hours: 24)}) =>
      db.syncedMissedDoseIdsSince(now.subtract(window));

  test('offers a missed dose', () async {
    await givenLog('a', action: DoseAction.missed, loggedAt: now.subtract(const Duration(hours: 1)));

    expect(await announceable(), ['a']);
  });

  test('says nothing about a dose that was taken', () async {
    await givenLog('a', action: DoseAction.taken, loggedAt: now.subtract(const Duration(hours: 1)));

    expect(await announceable(), isEmpty);
  });

  test('says nothing about a dose that was snoozed', () async {
    // A snooze is someone answering the alarm. They were reminded and said
    // "not yet", which is not an incident.
    await givenLog('a', action: DoseAction.snoozed, loggedAt: now.subtract(const Duration(hours: 1)));

    expect(await announceable(), isEmpty);
  });

  test('withholds a dose that has not reached the server yet', () async {
    // The server composes the notification by reading these rows back. Naming
    // one that exists only on this phone would have it find nothing to say.
    await givenLog(
      'a',
      action: DoseAction.missed,
      loggedAt: now.subtract(const Duration(hours: 1)),
      synced: false,
    );

    expect(await announceable(), isEmpty);
  });

  test('re-offers a dose that was already pushed', () async {
    // The whole point of asking the database instead of a sync call: an alert
    // lost to a failed request is offered again on the next foreground, and the
    // server's de-duplication means only the first offer ever rings anyone.
    await givenLog('a', action: DoseAction.missed, loggedAt: now.subtract(const Duration(hours: 1)));

    expect(await announceable(), ['a']);
    expect(await announceable(), ['a'], reason: 'asking twice must give the same answer');
  });

  test('drops a dose old enough that nobody could still act on it', () async {
    await givenLog('old', action: DoseAction.missed, loggedAt: now.subtract(const Duration(hours: 30)));
    await givenLog('recent', action: DoseAction.missed, loggedAt: now.subtract(const Duration(hours: 2)));

    expect(await announceable(), ['recent']);
  });

  test('returns the newest first, so a cap keeps what matters most', () async {
    await givenLog('older', action: DoseAction.missed, loggedAt: now.subtract(const Duration(hours: 6)));
    await givenLog('newer', action: DoseAction.missed, loggedAt: now.subtract(const Duration(hours: 1)));

    expect(await announceable(), ['newer', 'older']);
  });

  test('honours the cap', () async {
    for (var i = 0; i < 5; i++) {
      await givenLog('log-$i',
          action: DoseAction.missed, loggedAt: now.subtract(Duration(minutes: 10 * (i + 1))));
    }

    final ids = await db.syncedMissedDoseIdsSince(now.subtract(const Duration(hours: 24)), limit: 3);

    expect(ids, ['log-0', 'log-1', 'log-2']);
  });

  test('picks the missed ones out of a mixed batch', () async {
    await givenLog('taken-1', action: DoseAction.taken, loggedAt: now.subtract(const Duration(hours: 4)));
    await givenLog('missed-1', action: DoseAction.missed, loggedAt: now.subtract(const Duration(hours: 3)));
    await givenLog('snoozed-1', action: DoseAction.snoozed, loggedAt: now.subtract(const Duration(hours: 2)));
    await givenLog('missed-2', action: DoseAction.missed, loggedAt: now.subtract(const Duration(hours: 1)));

    expect(await announceable(), ['missed-2', 'missed-1']);
  });

  test('says nothing when there is nothing to say', () async {
    // The notifier short-circuits on an empty list rather than making a
    // round-trip to be told there is nothing to send.
    expect(await announceable(), isEmpty);
  });
}
