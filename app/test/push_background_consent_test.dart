import 'dart:io';

import 'package:dosely/core/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The silent `data_changed` push exists for the case where the app is *not*
/// in front of the user: a caregiver changes a reminder and the patient's
/// phone re-arms without anyone opening anything.
///
/// It runs on a fresh FCM isolate, where every app-wide singleton starts
/// empty. `AppSettings` is one of them, and `SyncService.pullAll` returns on
/// its first line unless cloud-backup consent is loaded — so a handler that
/// skipped `AppSettings.init()` pulled nothing and then re-armed the alarms
/// from an unchanged database. The push looked like it had worked.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => AppSettings.instance.resetForTest());

  test('an unloaded AppSettings reports consent as withheld', () async {
    SharedPreferences.setMockInitialValues({'consent_cloud_backup': true});

    expect(AppSettings.instance.consentCloudBackup, isFalse,
        reason: 'this is the state a fresh background isolate starts in');

    await AppSettings.instance.init();

    expect(AppSettings.instance.consentCloudBackup, isTrue,
        reason: 'the handler has to load it before it can sync');
  });

  test('the background handler loads settings before it pulls', () {
    // Asserted against the source: the handler itself needs Firebase and a
    // live platform channel, and the ordering is the whole fix — init has to
    // happen before applyRemoteDataChange, not after it.
    final source =
        File('lib/features/push/push_handlers.dart').readAsStringSync();
    final init = source.indexOf('AppSettings.instance.init()');
    final pull = source.indexOf('applyRemoteDataChange()');

    expect(init, isNonNegative,
        reason: 'without this the silent push is a no-op');
    expect(pull, isNonNegative);
    expect(init, lessThan(pull));
  });
}
