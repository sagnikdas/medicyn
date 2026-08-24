import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_supabase.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('the harness restores a signed-in session', () async {
    SharedPreferences.setMockInitialValues({});
    final backend = FakePostgrest();
    await initFakeSupabase(backend: backend, userId: 'user-1');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(Supabase.instance.client.auth.currentUser?.id, 'user-1');
  });
}
