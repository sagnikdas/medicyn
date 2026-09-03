import 'package:medicyn/core/theme.dart';
import 'package:medicyn/core/widgets/medicyn_chrome.dart';
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
          theme: MedicynTheme.light(),
          darkTheme: MedicynTheme.dark(),
          themeMode: ThemeMode.dark,
          home: Scaffold(
            body: const SizedBox.expand(child: ColoredBox(color: Colors.red)),
            bottomNavigationBar: MedicynBottomNav(
              index: 0,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      final nav = tester.getRect(find.byType(MedicynBottomNav));
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
