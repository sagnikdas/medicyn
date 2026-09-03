import 'package:medicyn/core/theme.dart';
import 'package:medicyn/features/insights/insights_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Most consistent card fits a narrow phone next to the streak', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: MedicynTheme.light(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Expanded(child: SizedBox(height: 120)),
                SizedBox(width: 12),
                Expanded(
                  child: InsightsMostConsistentCard(
                    label: 'Morning',
                    rate: 1,
                    expected: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Most consistent'), findsOneWidget);
    final label = tester.getRect(find.text('Most consistent'));
    expect(label.right, lessThanOrEqualTo(360 - 20));
    expect(tester.takeException(), isNull);
  });
}
