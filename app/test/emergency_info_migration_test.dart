import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicyn/data/local/database.dart';

/// Covers a real crash reported from a device: this app opens the same
/// encrypted file from more than one isolate (the main UI isolate and the
/// notification/FCM background isolate), and two of them racing the v9 -> v10
/// emergency-card migration on the same cold start left `allergies_severe`
/// already added to `emergency_info` while `PRAGMA user_version` stayed at 9
/// -- so every later attempt to open the database re-ran the same
/// `ALTER TABLE ADD COLUMN` and crashed with "duplicate column name",
/// which failed the whole database open (breaking every screen, not just
/// the emergency card).
///
/// Seeds an in-memory database shaped exactly like that device's: schema
/// version 9, with `allergies_severe` already present but the other four
/// v10 columns still missing, and opens it through the real `AppDatabase`
/// migration path.
void main() {
  QueryExecutor seedPartiallyMigratedV9Database() {
    return NativeDatabase.memory(
      setup: (rawDb) {
        rawDb.execute('''
          CREATE TABLE emergency_info (
            id TEXT NOT NULL PRIMARY KEY,
            blood_group TEXT NOT NULL DEFAULT '',
            allergies TEXT NOT NULL DEFAULT '',
            conditions TEXT NOT NULL DEFAULT '',
            updated_at TEXT NOT NULL
          );
        ''');
        // The column a previous, racing migration attempt already added --
        // the other four v10 columns are deliberately left missing, so this
        // also covers the migration correctly finishing the rest of the set.
        rawDb.execute('''
          ALTER TABLE emergency_info ADD COLUMN allergies_severe INTEGER NOT NULL DEFAULT 0 CHECK (allergies_severe IN (0, 1));
        ''');
        rawDb.execute('''
          INSERT INTO emergency_info (id, blood_group, allergies, conditions, updated_at)
          VALUES ('self', 'O+', 'Penicillin', '', '2026-08-01T09:00:00.000Z');
        ''');
        rawDb.execute('PRAGMA user_version = 9');
      },
    );
  }

  test(
    'opening a database where the v9->v10 migration partially ran does not crash',
    () async {
      final db = AppDatabase.forTesting(seedPartiallyMigratedV9Database());
      addTearDown(db.close);

      // Triggering any query forces the migration to run. This must not
      // throw "duplicate column name".
      final info = await db.emergencyInfoOnce();
      expect(info, isNotNull);
      expect(info!.bloodGroup, 'O+');
      expect(info.allergiesSevere, isFalse);

      // The rest of the v10 columns must have been added and be usable.
      await db.upsertEmergencyInfo(
        bloodGroup: 'O+',
        allergies: 'Penicillin',
        conditions: '',
        insuranceNumber: 'INS-1',
        nationalId: 'ID-1',
        healthCardNumber: 'HC-1',
      );
      final updated = await db.emergencyInfoOnce();
      expect(updated!.insuranceNumber, 'INS-1');
      expect(updated.nationalId, 'ID-1');
      expect(updated.healthCardNumber, 'HC-1');
    },
  );

  test(
    'a database that has fully finished the v9->v10 migration opens cleanly',
    () async {
      final db = AppDatabase.forTesting(
        NativeDatabase.memory(
          setup: (rawDb) {
            rawDb.execute('''
              CREATE TABLE emergency_info (
                id TEXT NOT NULL PRIMARY KEY,
                blood_group TEXT NOT NULL DEFAULT '',
                allergies TEXT NOT NULL DEFAULT '',
                allergies_severe INTEGER NOT NULL DEFAULT 0 CHECK (allergies_severe IN (0, 1)),
                conditions TEXT NOT NULL DEFAULT '',
                notes TEXT NOT NULL DEFAULT '',
                insurance_number TEXT NOT NULL DEFAULT '',
                national_id TEXT NOT NULL DEFAULT '',
                health_card_number TEXT NOT NULL DEFAULT '',
                updated_at TEXT NOT NULL
              );
            ''');
            rawDb.execute('PRAGMA user_version = 9');
          },
        ),
      );
      addTearDown(db.close);

      expect(await db.emergencyInfoOnce(), isNull);
    },
  );

  test(
    'a v10 database gains the emergency contact columns on upgrade to v11',
    () async {
      final db = AppDatabase.forTesting(
        NativeDatabase.memory(
          setup: (rawDb) {
            rawDb.execute('''
              CREATE TABLE emergency_info (
                id TEXT NOT NULL PRIMARY KEY,
                blood_group TEXT NOT NULL DEFAULT '',
                allergies TEXT NOT NULL DEFAULT '',
                allergies_severe INTEGER NOT NULL DEFAULT 0 CHECK (allergies_severe IN (0, 1)),
                conditions TEXT NOT NULL DEFAULT '',
                notes TEXT NOT NULL DEFAULT '',
                insurance_number TEXT NOT NULL DEFAULT '',
                national_id TEXT NOT NULL DEFAULT '',
                health_card_number TEXT NOT NULL DEFAULT '',
                updated_at TEXT NOT NULL
              );
            ''');
            rawDb.execute('''
              INSERT INTO emergency_info (id, blood_group, allergies, conditions, updated_at)
              VALUES ('self', 'O+', 'Penicillin', '', '2026-08-01T09:00:00.000Z');
            ''');
            rawDb.execute('PRAGMA user_version = 10');
          },
        ),
      );
      addTearDown(db.close);

      final info = await db.emergencyInfoOnce();
      expect(info!.bloodGroup, 'O+');
      expect(info.emergencyContactName, '');
      expect(info.emergencyContactPhone, '');

      await db.upsertEmergencyInfo(
        bloodGroup: 'O+',
        allergies: 'Penicillin',
        conditions: '',
        emergencyContactName: 'Priya Kapoor',
        emergencyContactPhone: '+919876500000',
      );
      final updated = await db.emergencyInfoOnce();
      expect(updated!.emergencyContactName, 'Priya Kapoor');
      expect(updated.emergencyContactPhone, '+919876500000');
    },
  );

  test(
    'a v9 database jumping straight to v11 gains every added column',
    () async {
      final db = AppDatabase.forTesting(seedPartiallyMigratedV9Database());
      addTearDown(db.close);

      final info = await db.emergencyInfoOnce();
      expect(info!.bloodGroup, 'O+');

      await db.upsertEmergencyInfo(
        bloodGroup: 'O+',
        allergies: 'Penicillin',
        conditions: '',
        emergencyContactName: 'Priya Kapoor',
        emergencyContactPhone: '+919876500000',
      );
      final updated = await db.emergencyInfoOnce();
      expect(updated!.emergencyContactName, 'Priya Kapoor');
      expect(updated.emergencyContactPhone, '+919876500000');
    },
  );
}
