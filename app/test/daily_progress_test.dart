import 'package:medicyn/core/theme.dart';
import 'package:medicyn/core/widgets/medicyn_chrome.dart';
import 'package:medicyn/features/reminders_home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('percent label is 100% when every dose is taken', () {
    expect(ProgressRing.percentLabel(1), '100%');
    expect(ProgressRing.percentLabel(0), '0%');
    expect(ProgressRing.percentLabel(0.5), '50%');
    expect(ProgressRing.percentLabel(4 / 4), '100%');
  });

  testWidgets('completed ring shows 100%, not a clipped 00%', (tester) async {
    await _pumpCard(tester, size: const Size(390, 844), taken: 4, expected: 4);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('00%'), findsNothing);
    expect(find.text('4 of 4 doses completed'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final title = tester.getRect(find.text('Daily progress'));
    final ring = tester.getRect(find.text('100%'));
    expect(ring.left, greaterThan(title.right));
  });

  testWidgets('empty ring shows 0%', (tester) async {
    await _pumpCard(tester, size: const Size(390, 844), taken: 0, expected: 4);
    expect(find.text('0%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in const [
    Size(320, 568),
    Size(360, 800),
    Size(390, 844),
    Size(768, 1024),
    Size(1024, 768),
  ]) {
    for (final scale in const [1.0, 1.5]) {
      testWidgets(
        'daily progress fits ${size.width.toInt()}x${size.height.toInt()} at ${(scale * 100).round()}%',
        (tester) async {
          await _pumpCard(
            tester,
            size: size,
            textScale: scale,
            taken: 4,
            expected: 4,
          );
          expect(find.text('100%'), findsOneWidget);
          expect(find.textContaining('4 of 4'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

Future<void> _pumpCard(
  WidgetTester tester, {
  required Size size,
  double textScale = 1,
  required int taken,
  required int expected,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: MedicynTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: size.width,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: DailyProgressCard(taken: taken, expected: expected),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
