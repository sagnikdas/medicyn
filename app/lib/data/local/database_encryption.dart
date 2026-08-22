import 'dart:convert';
import 'dart:typed_data';

/// The unencrypted file from before F-4, under the app documents directory
/// (`app_flutter/dosely.sqlite` on Android).
const plaintextDatabaseFileName = 'dosely.sqlite';

/// First 16 bytes of an unencrypted SQLite database: `SQLite format 3\0`.
/// Encrypted sqlite3mc/SQLCipher files do not start with this.
final Uint8List sqlitePlaintextHeader = Uint8List.fromList(
  const [0x53, 0x51, 0x4c, 0x69, 0x74, 0x65, 0x20, 0x66, 0x6f, 0x72, 0x6d, 0x61, 0x74, 0x20, 0x33, 0x00],
);

/// Owner id used when the user runs without a Google account. Names the
/// file `dosely-local.sqlite` via [encryptedDatabaseFileName].
const localOwnerUserId = 'local';

/// Encrypted, per-account file name. [userId] is the Supabase auth subject
/// (a uuid), or [localOwnerUserId] in local-only mode. Characters outside a
/// conservative filesystem set are replaced so a surprising id cannot escape
/// the documents directory by name.
String encryptedDatabaseFileName(String userId) =>
    'dosely-${sanitizeDatabaseUserId(userId)}.sqlite';

String sanitizeDatabaseUserId(String userId) {
  final safe = userId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  if (safe.isEmpty) {
    throw ArgumentError.value(userId, 'userId', 'Cannot name a database file');
  }
  return safe;
}

/// True for the per-account files this opener creates, and false for the
/// legacy `dosely.sqlite` name (no hyphenated suffix).
bool isPerUserDatabaseFileName(String name) =>
    RegExp(r'^dosely-[A-Za-z0-9._-]+\.sqlite$').hasMatch(name);

/// Whether [bytes] (at least the first 16, if present) are a plaintext
/// SQLite database header. Shorter blobs and encrypted files return false.
bool isPlaintextSqliteHeader(List<int> bytes) {
  if (bytes.length < sqlitePlaintextHeader.length) return false;
  for (var i = 0; i < sqlitePlaintextHeader.length; i++) {
    if (bytes[i] != sqlitePlaintextHeader[i]) return false;
  }
  return true;
}

/// What to do with a leftover `dosely.sqlite` when opening [dest]'s
/// per-user encrypted file.
enum PlaintextMigrationDecision {
  /// Copy into the encrypted dest, then delete the plaintext on success.
  migrate,

  /// Dest (or another per-user file) already holds the data. Delete the
  /// leftover plaintext; do not copy it into a second account's file.
  deleteLeftover,

  /// Leave the plaintext file alone — missing, not SQLite, or we cannot
  /// claim it yet.
  leaveAlone,
}

PlaintextMigrationDecision decidePlaintextMigration({
  required bool plaintextExists,
  required bool plaintextIsSqlite,
  required bool destExists,
  required bool anyPerUserDatabaseExists,
}) {
  if (!plaintextExists || !plaintextIsSqlite) {
    return PlaintextMigrationDecision.leaveAlone;
  }
  if (destExists || anyPerUserDatabaseExists) {
    return PlaintextMigrationDecision.deleteLeftover;
  }
  return PlaintextMigrationDecision.migrate;
}

/// Doubles single quotes so a path or key can be embedded in a SQL string
/// literal. Prefer hex keys, which need no escaping; this is for paths.
String escapeSqlString(String source) => source.replaceAll("'", "''");

/// `PRAGMA key` / `PRAGMA rekey` argument for a 32-byte key stored as 64
/// lowercase hex characters: `x'abcd...'`.
String sqlcipherHexKeyLiteral(String hexKey) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hexKey)) {
    throw ArgumentError.value(hexKey, 'hexKey', 'Expected 64 lowercase hex chars');
  }
  return "x'$hexKey'";
}

/// UTF-8 view of the documented header, for tests that want the string form.
String get sqlitePlaintextHeaderString => utf8.decode(sqlitePlaintextHeader.sublist(0, 15));
