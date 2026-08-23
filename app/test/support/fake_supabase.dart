import 'dart:convert';

import 'package:dosely/core/supabase_init.dart' as init;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Boots a real [Supabase] client whose transport is a stub, so services
/// that reach for `Supabase.instance.client` can be driven end to end
/// without a network or any change to the code under test.
const fakeSupabaseUrl = 'https://twybepxnqayypzljhcnx.supabase.co';

/// A signed-in session GoTrue will restore without calling out to refresh.
/// The signature is never verified client-side; only the `exp` claim is
/// read, and a token expiring in an hour keeps the session live.
String fakeAccessToken(String userId) {
  String seg(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final exp = DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
  return '${seg({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${seg({'sub': userId, 'exp': exp, 'role': 'authenticated'})}.sig';
}

String fakeSessionBlob(String userId) => jsonEncode({
      'access_token': fakeAccessToken(userId),
      'token_type': 'bearer',
      'expires_in': 3600,
      'refresh_token': 'refresh-token',
      'user': {
        'id': userId,
        'aud': 'authenticated',
        'email': 'parent@example.com',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-01-01T00:00:00Z',
      },
    });

class MemorySecureStore implements init.SecureKeyValueStore {
  MemorySecureStore([Map<String, String>? seed]) : data = {...?seed};
  final Map<String, String> data;

  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
}

/// One request the stub transport saw, in the shape assertions care about.
class RecordedRequest {
  RecordedRequest(this.method, this.url, this.body);
  final String method;
  final Uri url;
  final String body;

  String get table => url.pathSegments.last;
  List<Map<String, dynamic>> get rows {
    final decoded = jsonDecode(body);
    if (decoded is List) return decoded.cast<Map<String, dynamic>>();
    return [decoded as Map<String, dynamic>];
  }
}

/// Answers PostgREST calls from [tables], recording everything it is asked.
class FakePostgrest {
  FakePostgrest({Map<String, List<Map<String, dynamic>>>? tables})
      : tables = {...?tables};

  final Map<String, List<Map<String, dynamic>>> tables;
  final List<RecordedRequest> requests = [];

  /// Tables named here throw instead of answering, so a partial failure can
  /// be tested without pretending the whole sync fell over.
  final Set<String> failing = <String>{};

  /// Tables named here never answer, which is what a stalled connection
  /// looks like to the 8-second timeout in SyncService.
  final Set<String> hanging = <String>{};

  http.Client get client => MockClient((request) async {
        final body = request.body;
        final table = request.url.pathSegments.last;
        requests.add(RecordedRequest(request.method, request.url, body));
        if (hanging.contains(table)) {
          await Future<void>.delayed(const Duration(seconds: 30));
        }
        if (failing.contains(table)) {
          return http.Response(
            jsonEncode({'message': 'boom', 'code': '500'}),
            500,
            // postgrest dereferences response.request, so a stub that omits
            // it fails with a null-check error rather than the status.
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode(tables[table] ?? const []),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('[]', 200,
            request: request,
            headers: {'content-type': 'application/json'});
      });

  RecordedRequest? lastWriteTo(String table) {
    for (final r in requests.reversed) {
      if (r.table == table && r.method != 'GET') return r;
    }
    return null;
  }

  Iterable<RecordedRequest> writesTo(String table) =>
      requests.where((r) => r.table == table && r.method != 'GET');
}

Future<void> initFakeSupabase({
  required FakePostgrest backend,
  required String userId,
}) async {
  final key = init.supabasePersistSessionKey(fakeSupabaseUrl);
  await Supabase.initialize(
    url: fakeSupabaseUrl,
    anonKey: 'anon-key',
    httpClient: backend.client,
    authOptions: FlutterAuthClientOptions(
      autoRefreshToken: false,
      localStorage: init.SecureSupabaseLocalStorage(
        persistSessionKey: key,
        secureStore: MemorySecureStore({key: fakeSessionBlob(userId)}),
        loadPrefs: SharedPreferences.getInstance,
      ),
    ),
  );
}
