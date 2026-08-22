import 'package:dosely/core/motion.dart';
import 'package:dosely/core/theme.dart';
import 'package:dosely/core/widgets/dosely_chrome.dart';
import 'package:dosely/core/widgets/dosely_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('fade-in is a no-op when animations are disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: DoselyTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const Scaffold(body: DoselyFadeIn(child: Text('Hello'))),
      ),
    );

    expect(find.text('Hello'), findsOneWidget);
    expect(find.byType(Opacity), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('progress ring paints the target percent on the first frame', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: DoselyTheme.light(),
        home: const Scaffold(body: ProgressRing(fraction: 1)),
      ),
    );

    expect(find.text('100%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('progress ring tweens when the fraction changes', (tester) async {
    late StateSetter setState;
    var fraction = 0.0;

    await tester.pumpWidget(
      MaterialApp(
        theme: DoselyTheme.light(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, set) {
              setState = set;
              return ProgressRing(fraction: fraction);
            },
          ),
        ),
      ),
    );
    expect(find.text('0%'), findsOneWidget);

    setState(() => fraction = 1);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('progress ring snaps when animations are disabled', (
    tester,
  ) async {
    late StateSetter setState;
    var fraction = 0.0;

    await tester.pumpWidget(
      MaterialApp(
        theme: DoselyTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, set) {
              setState = set;
              return ProgressRing(fraction: fraction);
            },
          ),
        ),
      ),
    );

    setState(() => fraction = 1);
    await tester.pump();
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('indexed stack keeps every child mounted', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: DoselyTheme.light(),
        home: const Scaffold(
          body: DoselyIndexedStack(
            index: 0,
            children: [Text('today'), Text('plan')],
          ),
        ),
      ),
    );

    expect(find.text('today'), findsOneWidget);
    expect(find.text('plan', skipOffstage: false), findsOneWidget);
  });

  test('motion tokens stay short enough for a medicine reminder', () {
    expect(DoselyMotion.fast.inMilliseconds, lessThanOrEqualTo(200));
    expect(DoselyMotion.medium.inMilliseconds, lessThanOrEqualTo(300));
    expect(DoselyMotion.slow.inMilliseconds, lessThanOrEqualTo(400));
  });
}
