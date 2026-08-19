import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

/// The persist-session key supabase_flutter uses when no custom
/// [LocalStorage] is supplied: `sb-<project-ref>-auth-token`. Existing
/// installs already have the session under this name (SharedPreferences
/// writes it into the XML as `flutter.<key>`).
String supabasePersistSessionKey(String supabaseUrl) =>
    'sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token';

/// Shared by [main] and the FCM background isolate. They must agree on
/// [LocalStorage] or a push that arrives with the app dead cannot see the
/// session the UI signed in with.
Future<void> initializeSupabase() {
  return Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
    authOptions: FlutterAuthClientOptions(
      localStorage: SecureSupabaseLocalStorage(
        persistSessionKey: supabasePersistSessionKey(SupabaseConfig.url),
      ),
    ),
  );
}

/// Narrow key-value backend so [SecureSupabaseLocalStorage] can run its
/// prefs-to-secure migration in unit tests without a device Keystore.
abstract class SecureKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  FlutterSecureKeyValueStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              // EncryptedSharedPreferences is Keystore-backed and readable
              // from the FCM background isolate, which a process-private
              // Keystore blob is not always.
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// [LocalStorage] that keeps the GoTrue session in Keystore/Keychain and
/// copies any leftover plaintext SharedPreferences blob on first launch
/// after the upgrade, so already-signed-in users stay signed in.
class SecureSupabaseLocalStorage extends LocalStorage {
  SecureSupabaseLocalStorage({
    required this.persistSessionKey,
    SecureKeyValueStore? secureStore,
    Future<SharedPreferences> Function()? loadPrefs,
  })  : _secureStore = secureStore ?? FlutterSecureKeyValueStore(),
        _loadPrefs = loadPrefs ?? SharedPreferences.getInstance;

  final String persistSessionKey;
  final SecureKeyValueStore _secureStore;
  final Future<SharedPreferences> Function() _loadPrefs;

  @override
  Future<void> initialize() async {
    WidgetsFlutterBinding.ensureInitialized();
    await _migrateFromSharedPreferences();
  }

  @override
  Future<bool> hasAccessToken() async {
    final token = await accessToken();
    return token != null && token.isNotEmpty;
  }

  @override
  Future<String?> accessToken() => _secureStore.read(persistSessionKey);

  @override
  Future<void> persistSession(String persistSessionString) async {
    await _secureStore.write(persistSessionKey, persistSessionString);
    await _removeLegacyPrefs();
  }

  @override
  Future<void> removePersistedSession() async {
    await _secureStore.delete(persistSessionKey);
    await _removeLegacyPrefs();
  }

  Future<void> _migrateFromSharedPreferences() async {
    var session = await _secureStore.read(persistSessionKey);
    final prefs = await _loadPrefs();
    if (session == null || session.isEmpty) {
      final leftover = _legacySessionFromPrefs(prefs);
      if (leftover == null) return;
      await _secureStore.write(persistSessionKey, leftover);
      session = await _secureStore.read(persistSessionKey);
    }
    // Only drop the plaintext copy once the secure store actually holds it.
    // A failed write must not sign the user out.
    if (session != null && session.isNotEmpty) {
      await prefs.remove(persistSessionKey);
      await prefs.remove('flutter.$persistSessionKey');
    }
  }

  Future<void> _removeLegacyPrefs() async {
    final prefs = await _loadPrefs();
    await prefs.remove(persistSessionKey);
    await prefs.remove('flutter.$persistSessionKey');
  }

  /// SharedPreferences prefixes keys with `flutter.` in the on-disk XML,
  /// but the Dart API strips that prefix. Try both so a leftover written
  /// under either name still migrates.
  String? _legacySessionFromPrefs(SharedPreferences prefs) {
    for (final key in [persistSessionKey, 'flutter.$persistSessionKey']) {
      final value = prefs.getString(key);
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }
}
