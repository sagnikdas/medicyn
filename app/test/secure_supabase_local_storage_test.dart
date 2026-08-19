import 'package:dosely/core/supabase_config.dart';
import 'package:dosely/core/supabase_init.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The session used to live in plaintext prefs. These cover the one-shot
/// copy into the secure store, because dropping that copy would sign every
/// existing install out on first launch after the upgrade.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const persistSessionKey = 'sb-twybepxnqayypzljhcnx-auth-token';
  const sessionBlob = '{"access_token":"a","refresh_token":"r"}';

  late _MemorySecureStore secure;

  setUp(() {
    secure = _MemorySecureStore();
    SharedPreferences.setMockInitialValues({});
  });

  SecureSupabaseLocalStorage storage() => SecureSupabaseLocalStorage(
        persistSessionKey: persistSessionKey,
        secureStore: secure,
      );

  test('the persist key matches supabase_flutter default for this project', () {
    expect(
      supabasePersistSessionKey(SupabaseConfig.url),
      persistSessionKey,
    );
  });

  test('copies a leftover session from SharedPreferences, then deletes it', () async {
    SharedPreferences.setMockInitialValues({persistSessionKey: sessionBlob});

    await storage().initialize();

    expect(secure.data[persistSessionKey], sessionBlob);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(persistSessionKey), isNull);
    expect(prefs.getString('flutter.$persistSessionKey'), isNull);
  });

  test('also finds a leftover stored under the flutter. XML prefix', () async {
    // setMockInitialValues keeps keys that already start with `flutter.`,
    // then the Dart API strips one prefix — so a raw XML key of
    // `flutter.flutter.<persist>` is what `getString('flutter.<persist>')`
    // reads. That is the second lookup initialize() has to try.
    SharedPreferences.setMockInitialValues({
      'flutter.flutter.$persistSessionKey': sessionBlob,
    });

    await storage().initialize();

    expect(secure.data[persistSessionKey], sessionBlob);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(persistSessionKey), isNull);
    expect(prefs.getString('flutter.$persistSessionKey'), isNull);
  });

  test('does not overwrite a session already in secure storage', () async {
    secure.data[persistSessionKey] = '{"refresh_token":"kept"}';
    SharedPreferences.setMockInitialValues({persistSessionKey: sessionBlob});

    await storage().initialize();

    expect(secure.data[persistSessionKey], '{"refresh_token":"kept"}');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(persistSessionKey), isNull);
  });

  test('leaves prefs untouched when neither store has a session', () async {
    SharedPreferences.setMockInitialValues({'unrelated': 'keep'});

    await storage().initialize();

    expect(secure.data, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('unrelated'), 'keep');
  });

  test('persistSession writes secure storage and clears leftover prefs', () async {
    SharedPreferences.setMockInitialValues({persistSessionKey: 'stale'});
    final local = storage();
    await local.initialize();

    await local.persistSession(sessionBlob);

    expect(await local.accessToken(), sessionBlob);
    expect(await local.hasAccessToken(), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(persistSessionKey), isNull);
  });

  test('removePersistedSession drops both backends', () async {
    secure.data[persistSessionKey] = sessionBlob;
    SharedPreferences.setMockInitialValues({persistSessionKey: sessionBlob});
    final local = storage();
    await local.initialize();

    await local.removePersistedSession();

    expect(await local.hasAccessToken(), isFalse);
    expect(await local.accessToken(), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(persistSessionKey), isNull);
  });
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
