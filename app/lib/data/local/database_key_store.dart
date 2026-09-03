import 'dart:math';

import '../../core/supabase_init.dart';

/// Persists the database encryption key and the account that currently owns
/// the on-device medical file.
///
/// The key is generated once per install and stored via
/// [FlutterSecureKeyValueStore] (Android Keystore-backed
/// EncryptedSharedPreferences / iOS Keychain). Background isolates that
/// record Taken/Snooze must read the same values — they have no other way
/// to know which file to open after sign-out.
class DatabaseKeyStore {
  DatabaseKeyStore({SecureKeyValueStore? store})
      : _store = store ?? FlutterSecureKeyValueStore();

  static const encryptionKeyName = 'medicyn.db.encryption_key';
  static const ownerUserIdName = 'medicyn.db.owner_user_id';

  final SecureKeyValueStore _store;
  static final _rand = Random.secure();

  /// 32 cryptographically random bytes as 64 lowercase hex chars. Never log
  /// the return value.
  Future<String> getOrCreateKeyHex() async {
    final existing = await _store.read(encryptionKeyName);
    if (existing != null && existing.isNotEmpty) {
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(existing)) {
        throw StateError('Stored database encryption key is not a 64-char hex string');
      }
      return existing;
    }
    final bytes = List<int>.generate(32, (_) => _rand.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await _store.write(encryptionKeyName, hex);
    final persisted = await _store.read(encryptionKeyName);
    if (persisted != hex) {
      throw StateError('Failed to persist the database encryption key');
    }
    return hex;
  }

  Future<String?> readOwnerUserId() => _store.read(ownerUserIdName);

  Future<void> writeOwnerUserId(String userId) =>
      _store.write(ownerUserIdName, userId);
}
