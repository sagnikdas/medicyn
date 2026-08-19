import 'dart:io';

import 'package:dosely/core/supabase_init.dart';
import 'package:dosely/data/local/database.dart';
import 'package:dosely/data/local/database_encryption.dart';
import 'package:dosely/data/local/database_key_store.dart';
import 'package:dosely/data/local/encrypted_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  group('plaintext sqlite header', () {
    test('matches the documented SQLite format 3 magic', () {
      expect(sqlitePlaintextHeaderString, 'SQLite format 3');
      expect(isPlaintextSqliteHeader(sqlitePlaintextHeader), isTrue);
    });

    test('rejects an encrypted-looking or truncated prefix', () {
      expect(isPlaintextSqliteHeader(List.filled(16, 0)), isFalse);
      expect(isPlaintextSqliteHeader(sqlitePlaintextHeader.sublist(0, 15)), isFalse);
      expect(isPlaintextSqliteHeader([]), isFalse);
      final flipped = List<int>.from(sqlitePlaintextHeader)..[0] = 0x00;
      expect(isPlaintextSqliteHeader(flipped), isFalse);
    });
  });

  group('per-account file names', () {
    test('keeps the legacy name distinct from per-user files', () {
      expect(isPerUserDatabaseFileName(plaintextDatabaseFileName), isFalse);
      expect(isPerUserDatabaseFileName('dosely.sqlite'), isFalse);
    });

    test('gives different users different files', () {
      const a = '11111111-1111-1111-1111-111111111111';
      const b = '22222222-2222-2222-2222-222222222222';
      expect(encryptedDatabaseFileName(a), 'dosely-$a.sqlite');
      expect(encryptedDatabaseFileName(b), 'dosely-$b.sqlite');
      expect(encryptedDatabaseFileName(a), isNot(encryptedDatabaseFileName(b)));
      expect(isPerUserDatabaseFileName(encryptedDatabaseFileName(a)), isTrue);
    });

    test('sanitises surprising characters in the user id', () {
      expect(encryptedDatabaseFileName('alice/../bob'), 'dosely-alice_.._bob.sqlite');
    });
  });

  group('plaintext migration decision', () {
    test('copies plaintext into the first encrypted file', () {
      expect(
        decidePlaintextMigration(
          plaintextExists: true,
          plaintextIsSqlite: true,
          destExists: false,
          anyPerUserDatabaseExists: false,
        ),
        PlaintextMigrationDecision.migrate,
      );
    });

    test('does not copy leftover plaintext into a second account', () {
      expect(
        decidePlaintextMigration(
          plaintextExists: true,
          plaintextIsSqlite: true,
          destExists: false,
          anyPerUserDatabaseExists: true,
        ),
        PlaintextMigrationDecision.deleteLeftover,
      );
    });

    test('leaves a missing or non-sqlite file alone', () {
      expect(
        decidePlaintextMigration(
          plaintextExists: false,
          plaintextIsSqlite: false,
          destExists: false,
          anyPerUserDatabaseExists: false,
        ),
        PlaintextMigrationDecision.leaveAlone,
      );
      expect(
        decidePlaintextMigration(
          plaintextExists: true,
          plaintextIsSqlite: false,
          destExists: false,
          anyPerUserDatabaseExists: false,
        ),
        PlaintextMigrationDecision.leaveAlone,
      );
    });
  });

  group('DatabaseKeyStore', () {
    test('generates a 32-byte hex key once and reuses it', () async {
      final store = _MemorySecureStore();
      final keys = DatabaseKeyStore(store: store);
      final first = await keys.getOrCreateKeyHex();
      final second = await keys.getOrCreateKeyHex();
      expect(first, second);
      expect(first, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(store.data[DatabaseKeyStore.encryptionKeyName], first);
    });

    test('stores the owner user id next to the key', () async {
      final store = _MemorySecureStore();
      final keys = DatabaseKeyStore(store: store);
      expect(await keys.readOwnerUserId(), isNull);
      await keys.writeOwnerUserId('user-a');
      expect(await keys.readOwnerUserId(), 'user-a');
      await keys.writeOwnerUserId('user-b');
      expect(await keys.readOwnerUserId(), 'user-b');
    });
  });

  group('encrypted opener', () {
    test('migrates plaintext into the signed-in user file and isolates accounts', () async {
      if (!_sqlite3HasCipher()) {
        markTestSkipped('sqlite3mc native assets are not linked in this test run');
        return;
      }

      final docs = await Directory.systemTemp.createTemp('dosely-docs');
      final tmp = await Directory.systemTemp.createTemp('dosely-tmp');
      addTearDown(() async {
        await docs.delete(recursive: true);
        await tmp.delete(recursive: true);
      });

      final plaintext = File('${docs.path}/$plaintextDatabaseFileName');
      final source = sqlite3.open(plaintext.path);
      source
        ..execute('CREATE TABLE medicines (drug_name TEXT)')
        ..execute("INSERT INTO medicines VALUES ('Metformin')");
      source.close();
      expect(isPlaintextSqliteHeader(await _firstBytes(plaintext, 16)), isTrue);

      final store = _MemorySecureStore();
      String? user = 'user-a';
      final opener = EncryptedDatabaseOpener(
        keyStore: DatabaseKeyStore(store: store),
        lookupSignedInUserId: () => user,
        documentsDirectory: () async => docs,
        temporaryDirectory: () async => tmp,
      );

      final execA = await opener.open();
      await execA.close();

      final encryptedA = File('${docs.path}/${encryptedDatabaseFileName('user-a')}');
      expect(await encryptedA.exists(), isTrue);
      expect(await plaintext.exists(), isFalse);
      expect(isPlaintextSqliteHeader(await _firstBytes(encryptedA, 16)), isFalse);
      expect(store.data[DatabaseKeyStore.ownerUserIdName], 'user-a');

      final hexKey = store.data[DatabaseKeyStore.encryptionKeyName]!;
      final readBack = sqlite3.open(encryptedA.path);
      readBack.execute('PRAGMA key = "${sqlcipherHexKeyLiteral(hexKey)}";');
      expect(readBack.select('SELECT drug_name FROM medicines').first['drug_name'], 'Metformin');
      readBack.close();

      user = null;
      final execSignedOut = await opener.open();
      await execSignedOut.close();
      expect(store.data[DatabaseKeyStore.ownerUserIdName], 'user-a');

      user = 'user-b';
      final leftover = File('${docs.path}/$plaintextDatabaseFileName');
      final spoiler = sqlite3.open(leftover.path);
      spoiler
        ..execute('CREATE TABLE medicines (drug_name TEXT)')
        ..execute("INSERT INTO medicines VALUES ('Should-not-migrate')");
      spoiler.close();

      final execB = await opener.open();
      final dbB = AppDatabase.forTesting(execB);
      expect(await dbB.select(dbB.medicines).get(), isEmpty);
      await dbB.close();

      final encryptedB = File('${docs.path}/${encryptedDatabaseFileName('user-b')}');
      expect(await encryptedB.exists(), isTrue);
      expect(await leftover.exists(), isFalse);
      expect(store.data[DatabaseKeyStore.ownerUserIdName], 'user-b');

      final stillA = sqlite3.open(encryptedA.path);
      stillA.execute('PRAGMA key = "${sqlcipherHexKeyLiteral(hexKey)}";');
      expect(stillA.select('SELECT drug_name FROM medicines').first['drug_name'], 'Metformin');
      stillA.close();
    });
  });
}

bool _sqlite3HasCipher() {
  final probe = sqlite3.openInMemory();
  try {
    return probe.select('PRAGMA cipher;').isNotEmpty;
  } catch (_) {
    return false;
  } finally {
    probe.close();
  }
}

Future<List<int>> _firstBytes(File file, int n) async {
  final raf = await file.open();
  try {
    return await raf.read(n);
  } finally {
    await raf.close();
  }
}

class _MemorySecureStore implements SecureKeyValueStore {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> delete(String key) async {
    data.remove(key);
  }
}
