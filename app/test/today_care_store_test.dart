import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicyn/data/local/database.dart';
import 'package:medicyn/features/reminders_home/today_care_store.dart';

TodayCareReminder _reminder(String id, DateTime at) => TodayCareReminder(
  id: id,
  title: 'Blood test',
  kind: 'test',
  scheduledAt: at,
  location: 'Clinic',
  notes: 'Bring referral',
  reminderMinutes: 30,
  completed: false,
  updatedAt: DateTime.utc(2026, 9, 5),
  pendingSync: true,
  deleted: false,
);

void main() {
  late AppDatabase db;
  late TodayCareStore store;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    store = TodayCareStore(db);
  });
  tearDown(() => db.close());

  test(
    'care persists, updates, completes, restores and removes without medication rows',
    () async {
      final reminder = _reminder('care-1', DateTime(2026, 9, 5, 10));
      await store.save(reminder);
      final saved = (await store.watch().first).single;
      expect(saved.title, reminder.title);
      expect(saved.pendingSync, isTrue);
      await store.save(
        reminder.copyWith(title: 'Updated test', completed: true),
      );
      final completed = (await store.watch().first).single;
      expect(completed.title, 'Updated test');
      expect(completed.completed, isTrue);
      await store.save(reminder);
      expect((await store.watch().first).single.completed, isFalse);
      expect(await db.select(db.medicines).get(), isEmpty);
      expect(await db.select(db.schedules).get(), isEmpty);
      expect(await db.select(db.doseLogs).get(), isEmpty);
      await store.remove(reminder.id);
      expect(await store.watch().first, isEmpty);
    },
  );

  test('all care categories persist in chronological order', () async {
    for (final kind in TodayCareKind.values.reversed) {
      await store.save(
        _reminder(
          kind.name,
          DateTime(2026, 9, 5 + kind.index, 10),
        ).copyWith(kind: kind.name),
      );
    }
    final records = await store.watch().first;
    expect(
      records.map((r) => r.kind),
      TodayCareKind.values.map((kind) => kind.name),
    );
  });

  test('invalid reminders never create rows', () async {
    final reminder = _reminder('care-1', DateTime(2026, 9, 5));
    await expectLater(
      store.save(reminder.copyWith(title: '  ')),
      throwsArgumentError,
    );
    await expectLater(
      store.save(reminder.copyWith(kind: 'medicine')),
      throwsArgumentError,
    );
    await expectLater(
      store.save(reminder.copyWith(reminderMinutes: const Value(-1))),
      throwsArgumentError,
    );
    expect(await store.watch().first, isEmpty);
  });

  test('care IDs cannot collide with existing positive medicine alarm IDs', () {
    expect(TodayCareNotifications.idFor('care-1'), isNegative);
    expect(
      TodayCareNotifications.idFor('care-1'),
      greaterThanOrEqualTo(-0x80000000),
    );
    expect(
      TodayCareNotifications.idFor('care-1'),
      TodayCareNotifications.idFor('care-1'),
    );
  });

  test('v6 upgrade preserves medicines and care survives reopening', () async {
    final directory = await Directory.systemTemp.createTemp(
      'medicyn-today-migration-',
    );
    final file = File('${directory.path}/test.sqlite');
    var diskDb = AppDatabase.forTesting(NativeDatabase(file));
    try {
      await diskDb.upsertMedicine(
        MedicinesCompanion.insert(
          id: 'existing-medicine',
          drugName: 'Existing medicine',
        ),
      );
      // Recreate the exact previous version: same medication tables, no care
      // table. Reopening exercises the actual onUpgrade path.
      await diskDb.customStatement('DROP TABLE today_care_reminders');
      await diskDb.customStatement('PRAGMA user_version = 6');
      await diskDb.close();
      diskDb = AppDatabase.forTesting(NativeDatabase(file));
      final reminder = _reminder('care-1', DateTime(2026, 9, 5, 10));
      await TodayCareStore(diskDb).save(reminder);
      expect(
        (await diskDb.medicineById('existing-medicine'))?.drugName,
        'Existing medicine',
      );
      await diskDb.close();
      diskDb = AppDatabase.forTesting(NativeDatabase(file));
      final restored = (await TodayCareStore(diskDb).watch().first).single;
      expect(restored.title, reminder.title);
      expect(restored.scheduledAt, reminder.scheduledAt);
      expect(restored.pendingSync, isTrue);
    } finally {
      await diskDb.close();
      await directory.delete(recursive: true);
    }
  });

  test(
    'v7 upgrade preserves existing care entries and queues them for upload',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'medicyn-care-v7-',
      );
      final file = File('${directory.path}/v7.sqlite');
      var diskDb = AppDatabase.forTesting(NativeDatabase(file));
      try {
        await diskDb.customStatement('DROP TABLE today_care_reminders');
        await diskDb.customStatement('''CREATE TABLE today_care_reminders (
        id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, kind TEXT NOT NULL,
        scheduled_at TEXT NOT NULL, location TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '', reminder_minutes INTEGER,
        completed INTEGER NOT NULL DEFAULT 0
      )''');
        await diskDb.customStatement('''INSERT INTO today_care_reminders
        (id, title, kind, scheduled_at, location, notes, reminder_minutes, completed)
        VALUES ('legacy-care', 'MRI scan', 'scan', '2026-09-10T10:00:00.000Z',
        'Hospital', 'Bring referral', 60, 1)''');
        await diskDb.customStatement('PRAGMA user_version = 7');
        await diskDb.close();
        diskDb = AppDatabase.forTesting(NativeDatabase(file));
        final restored = (await TodayCareStore(diskDb).watch().first).single;
        expect(restored.title, 'MRI scan');
        expect(restored.location, 'Hospital');
        expect(restored.notes, 'Bring referral');
        expect(restored.reminderMinutes, 60);
        expect(restored.completed, isTrue);
        expect(restored.deleted, isFalse);
        expect(restored.pendingSync, isTrue);
        expect(await diskDb.unsyncedTodayCareReminders(), hasLength(1));
      } finally {
        await diskDb.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
