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

    test('local-only sentinel names dosely-local.sqlite', () {
      expect(localOwnerUserId, 'local');
      expect(encryptedDatabaseFileName(localOwnerUserId), 'dosely-local.sqlite');
      expect(isPerUserDatabaseFileName(encryptedDatabaseFileName(localOwnerUserId)), isTrue);
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

    test('local-only with no session opens dosely-local.sqlite and does not throw', () async {
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

      final store = _MemorySecureStore();
      final opener = EncryptedDatabaseOpener(
        keyStore: DatabaseKeyStore(store: store),
        lookupSignedInUserId: () => null,
        lookupLocalOnly: () => true,
        documentsDirectory: () async => docs,
        temporaryDirectory: () async => tmp,
      );

      final exec = await opener.open();
      final db = AppDatabase.forTesting(exec);
      expect(await db.select(db.medicines).get(), isEmpty);
      await db.close();

      final localFile = File('${docs.path}/${encryptedDatabaseFileName(localOwnerUserId)}');
      expect(await localFile.exists(), isTrue);
      expect(store.data[DatabaseKeyStore.ownerUserIdName], localOwnerUserId);
    });

    test('two Google users still get different files', () async {
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

      final store = _MemorySecureStore();
      String? user = 'user-a';
      final opener = EncryptedDatabaseOpener(
        keyStore: DatabaseKeyStore(store: store),
        lookupSignedInUserId: () => user,
        lookupLocalOnly: () => false,
        documentsDirectory: () async => docs,
        temporaryDirectory: () async => tmp,
      );

      final execA = await opener.open();
      final dbA = AppDatabase.forTesting(execA);
      expect(await dbA.select(dbA.medicines).get(), isEmpty);
      await dbA.close();
      user = 'user-b';
      final execB = await opener.open();
      final dbB = AppDatabase.forTesting(execB);
      expect(await dbB.select(dbB.medicines).get(), isEmpty);
      await dbB.close();

      final fileA = File('${docs.path}/${encryptedDatabaseFileName('user-a')}');
      final fileB = File('${docs.path}/${encryptedDatabaseFileName('user-b')}');
      expect(await fileA.exists(), isTrue);
      expect(await fileB.exists(), isTrue);
      expect(fileA.path, isNot(fileB.path));
      expect(store.data[DatabaseKeyStore.ownerUserIdName], 'user-b');
    });
  });

  group('adopt local-only on first sign-in', () {
    test('renames dosely-local.sqlite and sidecars onto a new account file', () async {
      expect(
        decideAdoptLocalDatabase(accountFileExists: false, localFileExists: true),
        LocalAdoptDecision.adopt,
      );

      final docs = await Directory.systemTemp.createTemp('dosely-adopt');
      addTearDown(() async {
        await docs.delete(recursive: true);
      });

      final local = File('${docs.path}/${encryptedDatabaseFileName(localOwnerUserId)}');
      await local.writeAsBytes(const [1, 2, 3]);
      await File('${local.path}-wal').writeAsBytes(const [4]);
      await File('${local.path}-shm').writeAsBytes(const [5]);

      const userId = 'user-a';
      final decision = await adoptLocalDatabaseIfNeeded(docs: docs, ownerUserId: userId);
      expect(decision, LocalAdoptDecision.adopt);

      final account = File('${docs.path}/${encryptedDatabaseFileName(userId)}');
      expect(await account.exists(), isTrue);
      expect(await account.readAsBytes(), const [1, 2, 3]);
      expect(await File('${account.path}-wal').readAsBytes(), const [4]);
      expect(await File('${account.path}-shm').readAsBytes(), const [5]);
      expect(await local.exists(), isFalse);
      expect(await File('${local.path}-wal').exists(), isFalse);
      expect(await File('${local.path}-shm').exists(), isFalse);
    });

    test('leaves dosely-local.sqlite in place when the account already has a file', () async {
      expect(
        decideAdoptLocalDatabase(accountFileExists: true, localFileExists: true),
        LocalAdoptDecision.leaveLocalInPlace,
      );
      expect(
        decideAdoptLocalDatabase(accountFileExists: false, localFileExists: false),
        LocalAdoptDecision.nothingToAdopt,
      );

      final docs = await Directory.systemTemp.createTemp('dosely-adopt');
      addTearDown(() async {
        await docs.delete(recursive: true);
      });

      const userId = 'user-a';
      final local = File('${docs.path}/${encryptedDatabaseFileName(localOwnerUserId)}');
      final account = File('${docs.path}/${encryptedDatabaseFileName(userId)}');
      await local.writeAsBytes(const [9]);
      await account.writeAsBytes(const [8]);

      final decision = await adoptLocalDatabaseIfNeeded(docs: docs, ownerUserId: userId);
      expect(decision, LocalAdoptDecision.leaveLocalInPlace);
      expect(await local.readAsBytes(), const [9]);
      expect(await account.readAsBytes(), const [8]);
    });

    test('first signed-in open adopts the local-only file', () async {
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

      final store = _MemorySecureStore();
      String? user;
      var localOnly = true;
      final opener = EncryptedDatabaseOpener(
        keyStore: DatabaseKeyStore(store: store),
        lookupSignedInUserId: () => user,
        lookupLocalOnly: () => localOnly,
        documentsDirectory: () async => docs,
        temporaryDirectory: () async => tmp,
      );

      final localExec = await opener.open();
      final localDb = AppDatabase.forTesting(localExec);
      expect(await localDb.select(localDb.medicines).get(), isEmpty);
      await localDb.close();
      final localFile = File('${docs.path}/${encryptedDatabaseFileName(localOwnerUserId)}');
      expect(await localFile.exists(), isTrue);

      user = 'user-a';
      localOnly = false;
      final signedIn = await opener.open();
      final signedInDb = AppDatabase.forTesting(signedIn);
      expect(await signedInDb.select(signedInDb.medicines).get(), isEmpty);
      await signedInDb.close();

      final accountFile = File('${docs.path}/${encryptedDatabaseFileName('user-a')}');
      expect(await accountFile.exists(), isTrue);
      expect(await localFile.exists(), isFalse);
      expect(store.data[DatabaseKeyStore.ownerUserIdName], 'user-a');
    });
  });

  group('wipeEncryptedDatabaseForUser', () {
    test('deletes this account file and sidecars, and leaves others alone', () async {
      final docs = await Directory.systemTemp.createTemp('dosely-wipe');
      addTearDown(() async {
        await docs.delete(recursive: true);
      });

      const userA = '11111111-1111-1111-1111-111111111111';
      const userB = '22222222-2222-2222-2222-222222222222';
      final target = File('${docs.path}/${encryptedDatabaseFileName(userA)}');
      final wal = File('${target.path}-wal');
      final shm = File('${target.path}-shm');
      final journal = File('${target.path}-journal');
      final other = File('${docs.path}/${encryptedDatabaseFileName(userB)}');
      final leftover = File('${docs.path}/$plaintextDatabaseFileName');

      await target.writeAsString('a-db');
      await wal.writeAsString('a-wal');
      await shm.writeAsString('a-shm');
      await journal.writeAsString('a-journal');
      await other.writeAsString('b-db');
      await leftover.writeAsString('legacy');

      await wipeEncryptedDatabaseForUser(
        userA,
        documentsDirectory: () async => docs,
      );

      expect(await target.exists(), isFalse);
      expect(await wal.exists(), isFalse);
      expect(await shm.exists(), isFalse);
      expect(await journal.exists(), isFalse);
      expect(await other.exists(), isTrue);
      expect(await leftover.exists(), isTrue);
      expect(await other.readAsString(), 'b-db');
      expect(await leftover.readAsString(), 'legacy');
    });

    test('does not throw when the file is already gone', () async {
      final docs = await Directory.systemTemp.createTemp('dosely-wipe-missing');
      addTearDown(() async {
        await docs.delete(recursive: true);
      });

      await wipeEncryptedDatabaseForUser(
        '33333333-3333-3333-3333-333333333333',
        documentsDirectory: () async => docs,
      );
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
