import 'package:dosely/core/theme.dart';
import 'package:dosely/core/widgets/dosely_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'bottom nav keeps its own height so Scaffold still has a body',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: DoselyTheme.light(),
          darkTheme: DoselyTheme.dark(),
          themeMode: ThemeMode.dark,
          home: Scaffold(
            body: const SizedBox.expand(child: ColoredBox(color: Colors.red)),
            bottomNavigationBar: DoselyBottomNav(
              index: 0,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      final nav = tester.getRect(find.byType(DoselyBottomNav));
      expect(
        nav.height,
        lessThan(160),
        reason: 'a full-height bar swallows Today and floats the tabs mid-screen',
      );
      expect(nav.bottom, 800);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Plan'), findsOneWidget);
    },
  );
}
