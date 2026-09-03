import 'package:medicyn/core/theme.dart';
import 'package:medicyn/features/reminders_home/calendar_collapse_sliver.dart';
import 'package:medicyn/features/reminders_home/day_dose_list.dart';
import 'package:medicyn/features/reminders_home/dose_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final clock = DateTime(2026, 8, 21, 15, 30);
  final selected = DateTime(2026, 8, 21);

  Widget calendar({bool month = false, TextScaler? textScaler}) {
    Widget home = Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          HomeCalendarSliver(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              child: DoseCalendar(
                selectedDay: selected,
                now: clock,
                marks: const {},
                monthExpanded: month,
                onSelectDay: (_) {},
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) =>
                  SizedBox(height: 72, child: Text('dose $index')),
              childCount: 20,
            ),
          ),
        ],
      ),
    );
    return MaterialApp(
      theme: MedicynTheme.light(),
      builder: textScaler == null
          ? null
          : (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: textScaler),
              child: child!,
            ),
      home: home,
    );
  }

  testWidgets(
    'scrolling the day list hides the calendar; scrolling down shows it',
    (tester) async {
      await tester.pumpWidget(calendar());

      final header = find.byKey(const ValueKey('collapsing-calendar-header'));
      final before = tester.getSize(header);
      expect(before.height, greaterThan(120));

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pumpAndSettle();

      if (header.evaluate().isNotEmpty) {
        expect(tester.getSize(header).height, lessThan(before.height));
      }

      await tester.drag(find.byType(CustomScrollView), const Offset(0, 400));
      await tester.pumpAndSettle();

      expect(header, findsOneWidget);
      expect(tester.getSize(header).height, closeTo(before.height, 1));
      expect(find.text('dose 0'), findsOneWidget);
    },
  );

  testWidgets('week calendar does not overflow at 150% text', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(calendar(textScaler: const TextScaler.linear(1.5)));

    expect(find.byType(DoseCalendar), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Month'), findsOneWidget);
    expect(find.text('21'), findsWidgets);
  });

  testWidgets('month calendar does not overflow at 150% text', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      calendar(month: true, textScaler: const TextScaler.linear(1.5)),
    );

    expect(find.byType(DoseCalendar), findsOneWidget);
    expect(find.text('31'), findsWidgets);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -120));
    await tester.pump();
  });

  testWidgets('home layout does not overflow at 150% text on a small phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: MedicynTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Builder(
          builder: (context) {
            return Scaffold(
              appBar: AppBar(
                title: const Text(
                  'Medicyn',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                actions: [
                  IconButton(
                    tooltip: 'My medicines',
                    onPressed: () {},
                    icon: const Icon(Icons.medication_outlined),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ],
              ),
              body: CustomScrollView(
                slivers: [
                  HomeCalendarSliver(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                      child: DoseCalendar(
                        selectedDay: selected,
                        now: clock,
                        marks: const {},
                        onSelectDay: (_) {},
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: WeekAdherenceLine(taken: 2, expected: 2),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Tomorrow, Sat 22 August',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 16),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                'dfrtfh 16',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    expect(find.text('Medicyn'), findsOneWidget);
    expect(find.byIcon(Icons.medication_outlined), findsOneWidget);
    expect(find.byType(DoseCalendar), findsOneWidget);
    expect(find.textContaining('taken this week'), findsOneWidget);
  });
}
