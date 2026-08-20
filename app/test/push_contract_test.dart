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
  final notifyCare = File(
    '${repoRoot.path}/supabase/functions/notify-care/index.ts',
  );
  final manifest = File(
    '${Directory.current.path}/android/app/src/main/AndroidManifest.xml',
  );

  group('event names', () {
    late String functionSource;

    setUpAll(() {
      expect(
        notifyCare.existsSync(),
        isTrue,
        reason:
            'the notify-care function has moved; this test needs its new path',
      );
      functionSource = notifyCare.readAsStringSync();
    });

    test('the function knows the missed-dose event by the name we send', () {
      expect(functionSource, contains('"$pushEventMissedDose"'));
    });

    test('the function knows the refill-low event by the name we send', () {
      expect(functionSource, contains('"$pushEventRefillLow"'));
    });

    test('the function knows the silent-device event by the name we send', () {
      expect(functionSource, contains('"$pushEventDeviceSilent"'));
    });

    test('the function labels its messages with the key we read them by', () {
      // The `data` map's discriminator. Read on every arriving message, in the
      // background isolate where nothing can report a mismatch.
      expect(functionSource, contains('$pushEventKey: "$pushEventMissedDose"'));
      expect(
        functionSource,
        contains('$pushEventKey: "$pushEventDataChanged"'),
      );
      expect(functionSource, contains('$pushEventKey: "$pushEventRefillLow"'));
      expect(functionSource, contains('$pushEventKey: "$pushEventDeviceSilent"'));
    });

    test('the function names the patient by the key the tap handler reads', () {
      expect(functionSource, contains('$pushPatientIdKey:'));
    });
  });

  group('care-alert channel id', () {
    test('the function addresses the channel this app creates', () {
      expect(notifyCare.readAsStringSync(), contains('"$careAlertChannelId"'));
    });

    test('FCM conceals care-alert copy on a secure lock screen', () {
      // Android draws the FCM notification itself when the app is dead, so
      // the visibility has to live on the payload, not only on the local
      // NotificationDetails the foreground path uses.
      final fcm = File(
        '${repoRoot.path}/supabase/functions/notify-care/fcm.ts',
      ).readAsStringSync();
      expect(fcm, contains('visibility: "PRIVATE"'));
    });

    test(
      "Android's fallback channel is the care-alert one, not the alarm one",
      () {
        // If this ever became the alarm channel, a "your mother missed a dose"
        // notification would loop its sound until dismissed.
        final xml = manifest.readAsStringSync();
        expect(
          xml,
          contains(
            'com.google.firebase.messaging.default_notification_channel_id',
          ),
        );
        expect(xml, contains('android:value="$careAlertChannelId"'));
        expect(xml, isNot(contains('android:value="$reminderChannelId"')));
      },
    );
  });
}
