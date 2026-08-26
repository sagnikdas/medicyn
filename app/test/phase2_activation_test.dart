import 'package:dosely/core/app_settings.dart';
import 'package:dosely/core/theme.dart';
import 'package:dosely/features/onboarding/onboarding_screen.dart';
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

  tearDown(AppSettings.instance.resetForTest);

  test(
    'snooze duration choices persist and reject unsupported values',
    () async {
      expect(AppSettings.snoozeOptions, [5, 10, 20, 30]);
      await AppSettings.instance.setSnoozeMinutes(20);
      expect(AppSettings.instance.snoozeMinutes, 20);

      AppSettings.instance.resetForTest();
      await AppSettings.instance.init();
      expect(AppSettings.instance.snoozeMinutes, 20);

      await AppSettings.instance.setSnoozeMinutes(7);
      expect(AppSettings.instance.snoozeMinutes, 20);
    },
  );

  testWidgets('first-session onboarding is concise and completes locally', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: DoselyTheme.light(), home: const OnboardingScreen()),
    );
    await tester.pump();

    expect(find.text('Scan your medicine label'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
    expect(find.text('Next'), findsNothing);
    expect(find.byType(PageView), findsOneWidget);

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(AppSettings.instance.hasSeenOnboarding, isTrue);
  });
}
