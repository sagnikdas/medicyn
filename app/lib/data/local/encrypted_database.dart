import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'database_encryption.dart';
import 'database_key_store.dart';

/// Single opener used by the UI isolate and by background isolates that
/// construct `AppDatabase()` themselves (Taken/Snooze, FCM). They must
/// share the key, the owner id, and the file or SQLite will see two
/// different databases — or worse, a key mismatch on the same file.
QueryExecutor openEncryptedAppDatabase({EncryptedDatabaseOpener? opener}) {
  final resolved = opener ?? EncryptedDatabaseOpener();
  return LazyDatabase(resolved.open);
}

class EncryptedDatabaseOpener {
  EncryptedDatabaseOpener({
    DatabaseKeyStore? keyStore,
    String? Function()? lookupSignedInUserId,
    Future<Directory> Function()? documentsDirectory,
    Future<Directory> Function()? temporaryDirectory,
  })  : _keyStore = keyStore ?? DatabaseKeyStore(),
        _lookupSignedInUserId = lookupSignedInUserId ?? _supabaseUserId,
        _documentsDirectory = documentsDirectory ?? getApplicationDocumentsDirectory,
        _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final DatabaseKeyStore _keyStore;
  final String? Function() _lookupSignedInUserId;
  final Future<Directory> Function() _documentsDirectory;
  final Future<Directory> Function() _temporaryDirectory;

  Future<QueryExecutor> open() async {
    final hexKey = await _keyStore.getOrCreateKeyHex();
    final userId = await _resolveOwnerUserId();
    final docs = await _documentsDirectory();
    final cache = await _temporaryDirectory();
    sqlite3.tempDirectory = cache.path;

    ensureSqlite3MultipleCiphers();

    final plaintext = File(p.join(docs.path, plaintextDatabaseFileName));
    final encrypted = File(p.join(docs.path, encryptedDatabaseFileName(userId)));
    final anyPerUser = await _anyPerUserDatabaseExists(docs);

    final decision = decidePlaintextMigration(
      plaintextExists: await plaintext.exists(),
      plaintextIsSqlite: await _fileIsPlaintextSqlite(plaintext),
      destExists: await encrypted.exists(),
      anyPerUserDatabaseExists: anyPerUser,
    );
    switch (decision) {
      case PlaintextMigrationDecision.migrate:
        await migratePlaintextDatabase(
          plaintext: plaintext,
          encrypted: encrypted,
          hexKey: hexKey,
        );
      case PlaintextMigrationDecision.deleteLeftover:
        await deleteSqliteSidecars(plaintext);
      case PlaintextMigrationDecision.leaveAlone:
        break;
    }

    return NativeDatabase.createInBackground(
      encrypted,
      setup: (rawDb) {
        rawDb.execute('PRAGMA key = "${sqlcipherHexKeyLiteral(hexKey)}";');
      },
    );
  }

  /// Prefer the signed-in account so a second Google user on this phone
  /// opens (or creates) their own file. Fall back to the stored owner so
  /// a background isolate after sign-out still finds the same reminders.
  Future<String> _resolveOwnerUserId() async {
    final signedIn = _lookupSignedInUserId();
    if (signedIn != null && signedIn.isNotEmpty) {
      final previous = await _keyStore.readOwnerUserId();
      if (previous != signedIn) {
        await _keyStore.writeOwnerUserId(signedIn);
      }
      return signedIn;
    }
    final stored = await _keyStore.readOwnerUserId();
    if (stored != null && stored.isNotEmpty) return stored;
    throw StateError('Cannot open the medical database without an account');
  }
}

String? _supabaseUserId() {
  try {
    return Supabase.instance.client.auth.currentUser?.id;
  } catch (_) {
    return null;
  }
}

/// Throws if this process linked vanilla SQLite. Writing "encrypted" files
/// without sqlite3mc would recreate the original finding: a `SQLite format 3`
/// header and recoverable drug names.
void ensureSqlite3MultipleCiphers() {
  final probe = sqlite3.openInMemory();
  try {
    if (probe.select('PRAGMA cipher;').isEmpty) {
      throw StateError(
        'SQLite3MultipleCiphers is not linked; refusing to open the medical database unencrypted.',
      );
    }
  } finally {
    probe.close();
  }
}

Future<bool> _fileIsPlaintextSqlite(File file) async {
  if (!await file.exists()) return false;
  final raf = await file.open();
  try {
    final header = await raf.read(sqlitePlaintextHeader.length);
    return isPlaintextSqliteHeader(header);
  } finally {
    await raf.close();
  }
}

Future<bool> _anyPerUserDatabaseExists(Directory docs) async {
  if (!await docs.exists()) return false;
  await for (final entity in docs.list(followLinks: false)) {
    if (entity is File && isPerUserDatabaseFileName(p.basename(entity.path))) {
      return true;
    }
  }
  return false;
}

/// Copy [plaintext] into [encrypted] via `VACUUM INTO` + `PRAGMA rekey`.
/// On failure the plaintext file is left in place and [encrypted] is not
/// left half-written — the next open retries.
Future<void> migratePlaintextDatabase({
  required File plaintext,
  required File encrypted,
  required String hexKey,
}) async {
  final tmp = File('${encrypted.path}.tmp');
  try {
    if (await tmp.exists()) await tmp.delete();
    await encrypted.parent.create(recursive: true);

    final source = sqlite3.open(plaintext.path);
    try {
      source.execute("VACUUM INTO '${escapeSqlString(tmp.path)}';");
    } finally {
      source.close();
    }

    final copy = sqlite3.open(tmp.path);
    try {
      copy.execute('PRAGMA rekey = "${sqlcipherHexKeyLiteral(hexKey)}";');
    } finally {
      copy.close();
    }

    if (!await tmp.exists()) {
      throw StateError('Encryption produced no database file');
    }
    await tmp.rename(encrypted.path);
    await deleteSqliteSidecars(plaintext);
  } catch (_) {
    try {
      if (await tmp.exists()) await tmp.delete();
    } catch (_) {}
    rethrow;
  }
}

/// Deletes [db] and the SQLite `-wal` / `-shm` / `-journal` sidecars next
/// to it. Does not touch any other file — in particular not another
/// account's `dosely-<id>.sqlite`, not leftover `dosely.sqlite`, and not
/// the Keystore encryption key (another account on this phone still needs
/// it).
Future<void> deleteSqliteSidecars(File db) async {
  for (final suffix in const ['', '-wal', '-shm', '-journal']) {
    final file = File('${db.path}$suffix');
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Leaving a sidecar is worse for privacy than for correctness; the
      // next successful open retries. Never delete a *different* database
      // from here.
    }
  }
}

/// Removes this account's encrypted database from [documentsDirectory]
/// (the app documents dir by default). Safe to call after sign-out, once
/// AuthGate has closed the open connection. Does not delete other
/// accounts' files on a shared phone.
Future<void> wipeEncryptedDatabaseForUser(
  String userId, {
  Future<Directory> Function()? documentsDirectory,
}) async {
  final docs = await (documentsDirectory ?? getApplicationDocumentsDirectory)();
  final db = File(p.join(docs.path, encryptedDatabaseFileName(userId)));
  // The file may still be closing on some platforms after sign-out. A few
  // short retries beat leaving the medical rows on disk.
  for (var attempt = 0; attempt < 5; attempt++) {
    await deleteSqliteSidecars(db);
    if (!await db.exists()) return;
    await Future<void>.delayed(Duration(milliseconds: 40 * (attempt + 1)));
  }
}
