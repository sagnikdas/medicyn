import 'dart:io';

import 'package:dosely/features/notification_engine/notification_service.dart';
import 'package:dosely/features/push/push_events.dart';
import 'package:flutter_test/flutter_test.dart';

/// Push depends on four files agreeing on some string literals, and every one
/// of those agreements fails *silently* when broken:
///
///  * Rename an event name in the edge function and it sends a message the
///    device receives and ignores. No error anywhere; the family simply never
///    hears about a missed dose.
///  * Change the Android channel id in one place and Android drops the
///    notification, because it is addressed to a channel that does not exist.
///
/// Neither shows up in `flutter analyze` — the files are in different languages
/// — so it is checked here instead, by reading them.
void main() {
  // Tests run from the `app/` directory; everything else is a sibling.
  final repoRoot = Directory.current.parent;
  final notifyCare = File('${repoRoot.path}/supabase/functions/notify-care/index.ts');
  final manifest = File('${Directory.current.path}/android/app/src/main/AndroidManifest.xml');

  group('event names', () {
    late String functionSource;

    setUpAll(() {
      expect(notifyCare.existsSync(), isTrue,
          reason: 'the notify-care function has moved; this test needs its new path');
      functionSource = notifyCare.readAsStringSync();
    });

    test('the function knows the missed-dose event by the name we send', () {
      expect(functionSource, contains('"$pushEventMissedDose"'));
    });

    test('the function knows the data-changed event by the name we send', () {
      expect(functionSource, contains('"$pushEventDataChanged"'));
    });

    test('the function labels its messages with the key we read them by', () {
      // The `data` map's discriminator. Read on every arriving message, in the
      // background isolate where nothing can report a mismatch.
      expect(functionSource, contains('$pushEventKey: "$pushEventMissedDose"'));
      expect(functionSource, contains('$pushEventKey: "$pushEventDataChanged"'));
    });

    test('the function names the patient by the key the tap handler reads', () {
      expect(functionSource, contains('$pushPatientIdKey:'));
    });

    test('the function labels a re-arm with the key the device reads', () {
      expect(functionSource, contains('$pushRearmKey: "$pushRearmYes"'));
      expect(functionSource, contains('$pushRearmKey: "$pushRearmNo"'));
    });

    test('the caregiver-facing change ping names no medicine', () {
      // The visible data_changed copy is composed in data_change.ts and must
      // stay generic: a lock-screen alert that quoted a drug name would be
      // the Phase 2 path recreating the 4.3d care-alert exposure.
      final dataChange = File('${repoRoot.path}/supabase/functions/notify-care/data_change.ts')
          .readAsStringSync();
      expect(dataChange, contains('A reminder was changed'));
      expect(dataChange, contains('Open Dosely to see what changed.'));
      expect(dataChange, isNot(contains('drug_name')));
    });
  });

  group('care-alert channel id', () {
    test('the function addresses the channel this app creates', () {
      expect(notifyCare.readAsStringSync(), contains('"$careAlertChannelId"'));
    });

    test("Android's fallback channel is the care-alert one, not the alarm one", () {
      // If this ever became the alarm channel, a "your mother missed a dose"
      // notification would loop its sound until dismissed.
      final xml = manifest.readAsStringSync();
      expect(xml, contains('com.google.firebase.messaging.default_notification_channel_id'));
      expect(xml, contains('android:value="$careAlertChannelId"'));
      expect(xml, isNot(contains('android:value="$reminderChannelId"')));
    });
  });
}
