import 'package:medicyn/core/theme.dart';
import 'package:medicyn/features/reminders_home/dose_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final clock = DateTime(2026, 8, 21, 15, 30);
  final selected = DateTime(2026, 8, 21);

  Widget harness({
    DateTime? selectedDay,
    DateTime? now,
    Map<DateTime, CalendarDayMarks> marks = const {},
    bool forceWeekView = false,
    ValueChanged<DateTime>? onSelectDay,
    TextScaler textScaler = const TextScaler.linear(1.0),
  }) {
    return MaterialApp(
      theme: MedicynTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: Scaffold(
        body: DoseCalendar(
          selectedDay: selectedDay ?? selected,
          now: now ?? clock,
          marks: marks,
          forceWeekView: forceWeekView,
          onSelectDay: onSelectDay ?? (_) {},
        ),
      ),
    );
  }

  testWidgets('tapping a day calls onSelectDay with a date-only DateTime', (
    tester,
  ) async {
    DateTime? got;
    await tester.pumpWidget(harness(onSelectDay: (d) => got = d));

    // 21 Aug 2026 is a Friday; the collapsed week is Sun 16 – Sat 22.
    await tester.tap(find.text('17'));
    await tester.pump();

    expect(got, DateTime(2026, 8, 17));
    expect(got!.hour, 0);
    expect(got!.minute, 0);
  });

  testWidgets('Today button selects today, date-only', (tester) async {
    DateTime? got;
    await tester.pumpWidget(
      harness(selectedDay: DateTime(2026, 8, 16), onSelectDay: (d) => got = d),
    );

    await tester.tap(find.widgetWithText(TextButton, 'Today'));
    await tester.pump();

    expect(got, DateTime(2026, 8, 21));
  });

  testWidgets('Month toggle reveals a later date in the month', (tester) async {
    await tester.pumpWidget(harness());

    expect(find.text('31'), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Month'));
    await tester.pump();

    expect(find.text('31'), findsWidgets);
    expect(find.widgetWithText(TextButton, 'Week'), findsOneWidget);
  });

  testWidgets('forceWeekView hides the Month control', (tester) async {
    await tester.pumpWidget(harness(forceWeekView: true));

    expect(find.widgetWithText(TextButton, 'Month'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Week'), findsNothing);
    expect(find.text('31'), findsNothing);
  });

  testWidgets('a marked day is exposed to semantics', (tester) async {
    await tester.pumpWidget(
      harness(
        marks: {
          // Time on the key — the widget must still find the day.
          DateTime(2026, 8, 21, 9, 15): const CalendarDayMarks(
            taken: true,
            pending: true,
          ),
        },
      ),
    );

    expect(find.text('21'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'21 August.*taken')), findsOneWidget);
  });

  test('August 2026 month grid is six weeks', () {
    expect(
      DoseCalendarMetrics.weekCount(month: true, anchor: DateTime(2026, 8, 21)),
      6,
    );
    expect(
      DoseCalendarMetrics.weekCount(
        month: false,
        anchor: DateTime(2026, 8, 21),
      ),
      1,
    );
  });

  testWidgets('layout metrics match the painted week and month heights', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    final context = tester.element(find.byType(DoseCalendar));
    final weekH = tester.getSize(find.byType(DoseCalendar)).height;
    expect(
      weekH,
      closeTo(
        DoseCalendarMetrics.extentOf(context, month: false, anchor: selected),
        1,
      ),
    );

    await tester.tap(find.widgetWithText(TextButton, 'Month'));
    await tester.pumpAndSettle();
    final monthH = tester.getSize(find.byType(DoseCalendar)).height;
    expect(
      monthH,
      closeTo(
        DoseCalendarMetrics.extentOf(context, month: true, anchor: selected),
        1,
      ),
    );
  });

  testWidgets('Month stays visible at 150% text', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const scaler = TextScaler.linear(1.5);
    await tester.pumpWidget(harness(textScaler: scaler));

    expect(find.widgetWithText(TextButton, 'Month'), findsOneWidget);
    final monthBtn = tester.getRect(find.widgetWithText(TextButton, 'Month'));
    final calendarRect = tester.getRect(find.byType(DoseCalendar));
    expect(monthBtn.right, lessThanOrEqualTo(calendarRect.right + 0.5));
    expect(monthBtn.width, greaterThan(48));

    final calendar = find.byType(DoseCalendar);
    final context = tester.element(calendar);
    expect(
      tester.getSize(calendar).height,
      closeTo(
        DoseCalendarMetrics.extentOf(context, month: false, anchor: selected),
        1,
      ),
    );
  });

  testWidgets('1.3 scale month grid still matches metrics', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const scaler = TextScaler.linear(1.3);
    await tester.pumpWidget(harness(textScaler: scaler));

    await tester.tap(find.widgetWithText(TextButton, 'Month'));
    await tester.pumpAndSettle();

    final calendar = find.byType(DoseCalendar);
    final context = tester.element(calendar);
    expect(
      tester.getSize(calendar).height,
      closeTo(
        DoseCalendarMetrics.extentOf(context, month: true, anchor: selected),
        1,
      ),
    );
  });
}
