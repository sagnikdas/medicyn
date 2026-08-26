import 'package:dosely/core/app_settings.dart';
import 'package:dosely/features/consent/consent_purpose.dart';
import 'package:dosely/features/consent/consent_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AppSettings.instance.resetForTest();
    await AppSettings.instance.init();
  });

  tearDown(() {
    AppSettings.instance.resetForTest();
  });

  group('defaults', () {
    test('every purpose starts unticked, and consents are unrecorded', () {
      expect(AppSettings.instance.hasRecordedConsents, isFalse);
      expect(AppSettings.instance.consentCloudBackup, isFalse);
      expect(AppSettings.instance.consentAnthropicParse, isFalse);
      expect(AppSettings.instance.consentGoogleSpeech, isFalse);
      expect(AppSettings.instance.consentCareShare, isFalse);
    });

    test(
      'an existing install that skipped onboarding still has no recorded consents',
      () async {
        SharedPreferences.setMockInitialValues({'has_seen_onboarding': true});
        AppSettings.instance.resetForTest();
        await AppSettings.instance.init();

        expect(AppSettings.instance.hasSeenOnboarding, isTrue);
        expect(AppSettings.instance.hasRecordedConsents, isFalse);
        expect(AppSettings.instance.consentCloudBackup, isFalse);
      },
    );
  });

  group('prefs', () {
    test('grant then withdraw round-trips through prefs', () async {
      await AppSettings.instance.setConsentCloudBackup(true);
      await AppSettings.instance.setConsentAnthropicParse(true);
      expect(AppSettings.instance.consentCloudBackup, isTrue);
      expect(AppSettings.instance.consentAnthropicParse, isTrue);

      AppSettings.instance.resetForTest();
      await AppSettings.instance.init();
      expect(AppSettings.instance.consentCloudBackup, isTrue);
      expect(AppSettings.instance.consentAnthropicParse, isTrue);

      await AppSettings.instance.setConsentCloudBackup(false);
      await AppSettings.instance.setConsentAnthropicParse(false);

      AppSettings.instance.resetForTest();
      await AppSettings.instance.init();
      expect(AppSettings.instance.consentCloudBackup, isFalse);
      expect(AppSettings.instance.consentAnthropicParse, isFalse);
    });

    test('recording consents persists the seen flag', () async {
      await AppSettings.instance.setHasRecordedConsents();
      expect(AppSettings.instance.hasRecordedConsents, isTrue);

      AppSettings.instance.resetForTest();
      await AppSettings.instance.init();
      expect(AppSettings.instance.hasRecordedConsents, isTrue);
    });

    test('processing choices are isolated by account owner', () async {
      const accountA = 'user-a';
      const accountB = 'user-b';

      await AppSettings.instance.activateConsentOwner(accountA);
      await AppSettings.instance.setConsentCloudBackup(true);
      await AppSettings.instance.setConsentAnthropicParse(true);
      await AppSettings.instance.setConsentGoogleSpeech(true);
      await AppSettings.instance.setConsentCareShare(true);
      await AppSettings.instance.setHasRecordedConsents();

      await AppSettings.instance.activateConsentOwner(accountB);
      expect(AppSettings.instance.consentOwnerId, accountB);
      expect(AppSettings.instance.hasRecordedConsents, isFalse);
      expect(AppSettings.instance.consentCloudBackup, isFalse);
      expect(AppSettings.instance.consentAnthropicParse, isFalse);
      expect(AppSettings.instance.consentGoogleSpeech, isFalse);
      expect(AppSettings.instance.consentCareShare, isFalse);

      await AppSettings.instance.activateConsentOwner(accountA);
      expect(AppSettings.instance.hasRecordedConsents, isTrue);
      expect(AppSettings.instance.consentCloudBackup, isTrue);
      expect(AppSettings.instance.consentAnthropicParse, isTrue);
      expect(AppSettings.instance.consentGoogleSpeech, isTrue);
      expect(AppSettings.instance.consentCareShare, isTrue);
    });

    test('legacy device-wide choices migrate only to local owner', () async {
      SharedPreferences.setMockInitialValues({
        'has_recorded_consents': true,
        'consent_cloud_backup': true,
      });
      AppSettings.instance.resetForTest();

      await AppSettings.instance.init(consentOwnerId: 'signed-in-user');
      expect(AppSettings.instance.hasRecordedConsents, isFalse);
      expect(AppSettings.instance.consentCloudBackup, isFalse);

      await AppSettings.instance.activateConsentOwner(
        AppSettings.localConsentOwnerId,
      );
      expect(AppSettings.instance.hasRecordedConsents, isTrue);
      expect(AppSettings.instance.consentCloudBackup, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('has_recorded_consents'), isFalse);
      expect(prefs.containsKey('consent_cloud_backup'), isFalse);
    });
  });

  group('consent copy hash', () {
    test('is sha256 hex of the exact on-screen sentence', () {
      expect(
        ConsentPurpose.cloudBackup.textHash,
        'dc0d6056f41a6620e74861be0e33d8eedbfd6c245bbf78b18c96b6e17d4e6f42',
      );
      expect(
        ConsentPurpose.anthropicParse.textHash,
        '1a6b40f2ef20243d2bb1ac250e06a6cf9a3722e69af3f8dc59fa8c7bc217d34a',
      );
      expect(
        ConsentPurpose.googleSpeech.textHash,
        '7999853f37e3be4204daf3def055ffc0f447dc77530b42d60483044d23e729e1',
      );
      expect(
        ConsentPurpose.careShare.textHash,
        '16887cdb694ebbe952d2743b7505f460be679b8fae8a1bc2c6149ad08075c699',
      );
    });

    test('is stable across repeated computations', () {
      expect(
        ConsentPurpose.anthropicParse.textHash,
        ConsentPurpose.anthropicParse.textHash,
      );
      expect(ConsentPurpose.cloudBackup.textHash.length, 64);
    });

    test('first screen does not include care-share', () {
      expect(
        ConsentPurpose.firstScreen,
        isNot(contains(ConsentPurpose.careShare)),
      );
      expect(ConsentPurpose.firstScreen, hasLength(3));
    });
  });

  group('shouldParseMedicine', () {
    test('skips the edge function when Anthropic is not granted', () {
      expect(
        shouldParseMedicine(
          anthropicGranted: false,
          ocrText: 'METFORMIN 500mg',
          transcript: 'one tablet twice a day',
        ),
        isFalse,
      );
    });

    test('skips when there is nothing to parse, even if granted', () {
      expect(
        shouldParseMedicine(
          anthropicGranted: true,
          ocrText: '',
          transcript: '',
        ),
        isFalse,
      );
    });

    test('parses when granted and there is label or speech text', () {
      expect(
        shouldParseMedicine(
          anthropicGranted: true,
          ocrText: 'Aspirin',
          transcript: '',
        ),
        isTrue,
      );
      expect(
        shouldParseMedicine(
          anthropicGranted: true,
          ocrText: '',
          transcript: 'one at night',
        ),
        isTrue,
      );
    });
  });

  group('ConsentScreen', () {
    testWidgets('shows three unticked purposes and Continue is enabled', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ConsentScreen()));

      final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
      expect(switches, hasLength(3));
      expect(switches.every((s) => s.value == false), isTrue);

      expect(find.text('Share with family'), findsNothing);
      expect(find.text(ConsentPurpose.careShare.sentence), findsNothing);

      await tester.scrollUntilVisible(find.text('Privacy policy'), 80);
      expect(find.text('Privacy policy'), findsOneWidget);

      final continueButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Continue'),
      );
      expect(continueButton.onPressed, isNotNull);
    });

    testWidgets('Continue records consents even when everything stays off', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ConsentScreen()));

      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(AppSettings.instance.hasRecordedConsents, isTrue);
      expect(AppSettings.instance.consentCloudBackup, isFalse);
      expect(AppSettings.instance.consentAnthropicParse, isFalse);
      expect(AppSettings.instance.consentGoogleSpeech, isFalse);
    });
  });
}
