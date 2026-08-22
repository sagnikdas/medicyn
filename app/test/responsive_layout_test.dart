import 'package:dosely/core/theme.dart';
import 'package:dosely/core/widgets/dosely_chrome.dart';
import 'package:dosely/core/widgets/dosely_layout.dart';
import 'package:dosely/features/consent/consent_screen.dart';
import 'package:dosely/features/insights/insights_screen.dart';
import 'package:dosely/features/onboarding/onboarding_screen.dart';
import 'package:dosely/features/reminders_home/dose_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _phones = [Size(320, 568), Size(360, 800), Size(390, 844)];

const _tablets = [Size(768, 1024), Size(1024, 768)];

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  double textScale = 1,
  required Widget home,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: DoselyTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: home,
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('DoselyContent caps tablet width and fills a phone', (
    tester,
  ) async {
    const panel = Key('panel');
    await _pump(
      tester,
      size: const Size(1024, 768),
      home: const Scaffold(
        body: DoselyContent(
          child: ColoredBox(key: panel, color: Colors.red),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(panel)).width, DoselyContent.maxWidth);

    await _pump(
      tester,
      size: const Size(360, 800),
      home: const Scaffold(
        body: DoselyContent(
          child: ColoredBox(key: panel, color: Colors.red),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(panel)).width, 360);
  });

  for (final size in [..._phones, ..._tablets]) {
    testWidgets('bottom nav fits $size', (tester) async {
      await _pump(
        tester,
        size: size,
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: DoselyBottomNav(index: 2, onChanged: (_) {}),
        ),
      );
      expect(find.text('Insights'), findsOneWidget);
      final nav = tester.getRect(find.byType(DoselyBottomNav));
      expect(nav.width, size.width);
      expect(nav.right, lessThanOrEqualTo(size.width + 0.5));
    });
  }

  for (final size in _phones) {
    for (final scale in const [1.0, 1.5]) {
      testWidgets('Insights pair fits $size at ${scale}x', (tester) async {
        await _pump(
          tester,
          size: size,
          textScale: scale,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Expanded(child: SizedBox(height: 80)),
                  SizedBox(width: 12),
                  Expanded(
                    child: InsightsMostConsistentCard(
                      label: 'Afternoon',
                      rate: 1,
                      expected: 2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        expect(find.text('Most consistent'), findsOneWidget);
        final label = tester.getRect(find.text('Most consistent'));
        expect(label.right, lessThanOrEqualTo(size.width - 20 + 0.5));
      });
    }
  }

  for (final size in [..._phones, ..._tablets]) {
    testWidgets('calendar week strip fits $size', (tester) async {
      final now = DateTime(2026, 8, 22, 9);
      await _pump(
        tester,
        size: size,
        home: Scaffold(
          body: DoseCalendar(
            selectedDay: now,
            now: now,
            marks: const {},
            onSelectDay: (_) {},
          ),
        ),
      );
      expect(find.text('Today'), findsOneWidget);
    });
  }

  testWidgets('onboarding fits a small phone at 150%', (tester) async {
    await _pump(
      tester,
      size: const Size(320, 568),
      textScale: 1.5,
      home: const OnboardingScreen(),
    );
    expect(find.text('Scan your medicine label'), findsOneWidget);
  });

  testWidgets('onboarding fits a tablet', (tester) async {
    await _pump(
      tester,
      size: const Size(1024, 768),
      home: const OnboardingScreen(),
    );
    expect(find.text('Scan your medicine label'), findsOneWidget);
  });

  testWidgets('consent fits a small phone at 150%', (tester) async {
    await _pump(
      tester,
      size: const Size(320, 568),
      textScale: 1.5,
      home: const ConsentScreen(),
    );
    expect(find.text('What Dosely may do'), findsOneWidget);
  });

  testWidgets('profile row wraps a long subtitle', (tester) async {
    await _pump(
      tester,
      size: const Size(320, 568),
      textScale: 1.5,
      home: Scaffold(
        body: ProfileMenuRow(
          icon: Icons.people_outline,
          title: 'Connect with family',
          subtitle:
              'Let one person help you keep track of your medicines — or help someone else with theirs.',
          onTap: () {},
        ),
      ),
    );
    expect(find.text('Connect with family'), findsOneWidget);
  });
}
