import 'package:dosely/features/reminders_home/day_dose_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('WeekAdherenceLine hides when nothing is expected', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: WeekAdherenceLine(taken: 0, expected: 0)),
      ),
    );

    expect(find.textContaining('taken this week'), findsNothing);
    expect(tester.getSize(find.byType(WeekAdherenceLine)), Size.zero);
  });

  testWidgets('WeekAdherenceLine shows taken of expected', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: WeekAdherenceLine(taken: 6, expected: 8)),
      ),
    );

    expect(find.text('6 of 8 taken this week'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });
}
