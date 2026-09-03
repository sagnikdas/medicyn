import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_settings.dart';
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
    bool Function()? lookupLocalOnly,
    Future<Directory> Function()? documentsDirectory,
    Future<Directory> Function()? temporaryDirectory,
  })  : _keyStore = keyStore ?? DatabaseKeyStore(),
        _lookupSignedInUserId = lookupSignedInUserId ?? _supabaseUserId,
        _lookupLocalOnly = lookupLocalOnly ?? _appSettingsLocalOnly,
        _documentsDirectory = documentsDirectory ?? getApplicationDocumentsDirectory,
        _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final DatabaseKeyStore _keyStore;
  final String? Function() _lookupSignedInUserId;
  final bool Function() _lookupLocalOnly;
  final Future<Directory> Function() _documentsDirectory;
  final Future<Directory> Function() _temporaryDirectory;

  Future<QueryExecutor> open() async {
    // Independent of each other — key/owner resolution reads Keystore, the
    // two directories go through path_provider — so starting all four
    // before awaiting any of them turns four sequential platform-channel
    // round trips into the cost of the slowest one. This runs on the UI
    // isolate on every cold start, before the first medicine can appear.
    final hexKeyFuture = _keyStore.getOrCreateKeyHex();
    final userIdFuture = _resolveOwnerUserId();
    final docsFuture = _documentsDirectory();
    final cacheFuture = _temporaryDirectory();
    final hexKey = await hexKeyFuture;
    final userId = await userIdFuture;
    final docs = await docsFuture;
    final cache = await cacheFuture;
    sqlite3.tempDirectory = cache.path;

    ensureSqlite3MultipleCiphers();

    await adoptLocalDatabaseIfNeeded(docs: docs, ownerUserId: userId);

    final plaintext = File(p.join(docs.path, plaintextDatabaseFileName));
    final encrypted = File(p.join(docs.path, encryptedDatabaseFileName(userId)));

    // decidePlaintextMigration() falls straight through to leaveAlone
    // whenever there's no plaintext file to migrate — true of effectively
    // every open past the one-time F-4 migration. destExists and
    // anyPerUserDatabaseExists only ever feed that decision, so skip them
    // (and, for anyPerUserDatabaseExists, the full documents-directory
    // listing) rather than paying for them on every single cold start.
    final plaintextExists = await plaintext.exists();
    final plaintextIsSqlite =
        plaintextExists && await _fileIsPlaintextSqlite(plaintext);
    final decision = decidePlaintextMigration(
      plaintextExists: plaintextExists,
      plaintextIsSqlite: plaintextIsSqlite,
      destExists: plaintextIsSqlite ? await encrypted.exists() : false,
      anyPerUserDatabaseExists:
          plaintextIsSqlite ? await _anyPerUserDatabaseExists(docs) : false,
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
  ///
  /// Local-only writes [localOwnerUserId] into the keystore on first open
  /// so Taken/Snooze isolates can find `medicyn-local.sqlite` without
  /// reading prefs (AppSettings is not initialized there).
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
    if (_lookupLocalOnly()) {
      await _keyStore.writeOwnerUserId(localOwnerUserId);
      return localOwnerUserId;
    }
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

/// Defaults to [AppSettings.localOnly]. Background isolates must not rely
/// on this — they resolve the file from the keystore owner written on the
/// first local-only open. A missing or uninitialized singleton is treated
/// as not local-only.
bool _appSettingsLocalOnly() {
  try {
    return AppSettings.instance.localOnly;
  } catch (_) {
    return false;
  }
}

/// What to do with `medicyn-local.sqlite` when a Google session is opening
/// its per-account file for the first time on this phone.
enum LocalAdoptDecision {
  /// Rename the local-only file (and sidecars) to the account name so
  /// reminders are not stranded.
  adopt,

  /// This Google user already has a file; leave local-only data in place.
  leaveLocalInPlace,

  /// No local-only file to move, or the opener is itself in local-only.
  nothingToAdopt,
}

LocalAdoptDecision decideAdoptLocalDatabase({
  required bool accountFileExists,
  required bool localFileExists,
}) {
  if (accountFileExists) return LocalAdoptDecision.leaveLocalInPlace;
  if (localFileExists) return LocalAdoptDecision.adopt;
  return LocalAdoptDecision.nothingToAdopt;
}

/// If this is the first time [ownerUserId] has a file on this phone and
/// local-only data exists, rename `medicyn-local.sqlite` (including WAL/SHM
/// sidecars) to the account file. Never overwrite an existing account file.
Future<LocalAdoptDecision> adoptLocalDatabaseIfNeeded({
  required Directory docs,
  required String ownerUserId,
}) async {
  if (ownerUserId == localOwnerUserId) {
    return LocalAdoptDecision.nothingToAdopt;
  }
  final account = File(p.join(docs.path, encryptedDatabaseFileName(ownerUserId)));
  final local = File(p.join(docs.path, encryptedDatabaseFileName(localOwnerUserId)));
  final decision = decideAdoptLocalDatabase(
    accountFileExists: await account.exists(),
    localFileExists: await local.exists(),
  );
  if (decision == LocalAdoptDecision.adopt) {
    await renameSqliteWithSidecars(from: local, to: account);
  }
  return decision;
}

/// Renames a SQLite main file and any `-wal` / `-shm` / `-journal` sidecars
/// that sit next to it, so an adopted database keeps its WAL state.
Future<void> renameSqliteWithSidecars({
  required File from,
  required File to,
}) async {
  await to.parent.create(recursive: true);
  for (final suffix in _sqliteSidecarSuffixes) {
    final src = File('${from.path}$suffix');
    if (!await src.exists()) continue;
    final dest = File('${to.path}$suffix');
    if (await dest.exists()) await dest.delete();
    await src.rename(dest.path);
  }
}

const _sqliteSidecarSuffixes = ['', '-wal', '-shm', '-journal'];

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
/// account's `medicyn-<id>.sqlite`, not leftover `medicyn.sqlite`, and not
/// the Keystore encryption key (another account on this phone still needs
/// it).
Future<void> deleteSqliteSidecars(File db) async {
  for (final suffix in _sqliteSidecarSuffixes) {
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
