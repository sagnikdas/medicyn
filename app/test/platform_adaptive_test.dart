import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicyn/core/theme.dart';
import 'package:medicyn/core/widgets/medicyn_chrome.dart';
import 'package:medicyn/core/widgets/medicyn_platform.dart';

Widget _app({required TargetPlatform platform, required Widget child}) {
  return MaterialApp(
    theme: MedicynTheme.light().copyWith(platform: platform),
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('iOS uses Cupertino bottom tabs and controls', (tester) async {
    await tester.pumpWidget(
      _app(
        platform: TargetPlatform.iOS,
        child: Column(
          children: [
            MedicynAdaptiveSwitch(value: false, onChanged: (_) {}),
            Expanded(child: MedicynBottomNav(index: 0, onChanged: (_) {})),
          ],
        ),
      ),
    );

    expect(find.byType(CupertinoSwitch), findsOneWidget);
    expect(find.byType(CupertinoTabBar), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('Android keeps Material bottom tabs and controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        platform: TargetPlatform.android,
        child: Column(
          children: [
            MedicynAdaptiveSwitch(value: false, onChanged: (_) {}),
            Expanded(child: MedicynBottomNav(index: 0, onChanged: (_) {})),
          ],
        ),
      ),
    );

    expect(find.byType(Switch), findsOneWidget);
    expect(find.byType(CupertinoSwitch), findsNothing);
    expect(find.byType(CupertinoTabBar), findsNothing);
    expect(find.text('Today'), findsOneWidget);
  });

  testWidgets('back affordance follows platform convention', (tester) async {
    await tester.pumpWidget(
      _app(
        platform: TargetPlatform.iOS,
        child: const MedicynAdaptiveBackButton(),
      ),
    );
    expect(find.byIcon(CupertinoIcons.chevron_back), findsOneWidget);

    await tester.pumpWidget(
      _app(
        platform: TargetPlatform.android,
        child: const MedicynAdaptiveBackButton(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
  });
}
