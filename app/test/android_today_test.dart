import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicyn/core/theme.dart';
import 'package:medicyn/core/widgets/medicyn_chrome.dart';
import 'package:medicyn/data/local/database.dart';
import 'package:medicyn/features/reminders_home/android_today_screen.dart';
import 'package:medicyn/features/reminders_home/day_occurrences.dart';
import 'package:medicyn/features/reminders_home/dose_calendar.dart';
import 'package:medicyn/features/reminders_home/today_care_editor.dart';
import 'package:medicyn/features/reminders_home/today_care_store.dart';

final _now = DateTime(2026, 9, 5, 9);

DayOccurrence _dose({
  String name = 'Metformin',
  int hour = 9,
  DayDoseStatus status = DayDoseStatus.pending,
}) => DayOccurrence(
  item: ScheduleWithMedicine(
    Schedule(
      id: 'schedule-$name',
      medicineId: name,
      frequencyType: 'daily',
      times: const ['09:00', '20:00'],
      daysOfWeek: const [],
      active: true,
      createdAt: DateTime(2026, 8),
      updatedAt: DateTime(2026, 8),
      timingDefinedAt: DateTime(2026, 8),
      pendingSync: false,
      deleted: false,
    ),
    Medicine(
      id: name,
      drugName: name,
      strength: '500 mg',
      form: 'tablet',
      doseAmount: '1 tablet',
      notes: 'After food',
      createdAt: DateTime(2026, 8),
      updatedAt: DateTime(2026, 8),
      pendingSync: false,
      deleted: false,
    ),
  ),
  scheduledAt: DateTime(2026, 9, 5, hour),
  status: status,
);

TodayCareReminder _care({
  String title = 'Blood test',
  int day = 5,
  int hour = 13,
  bool completed = false,
  String kind = 'test',
}) => TodayCareReminder(
  id: '$title-$day',
  title: title,
  kind: kind,
  scheduledAt: DateTime(2026, 9, day, hour, 30),
  location: 'City clinic',
  notes: '',
  completed: completed,
  reminderMinutes: 30,
  updatedAt: DateTime.utc(2026, 9, 5),
  pendingSync: true,
  deleted: false,
);

TodayAgenda _agenda({
  List<DayOccurrence>? doses,
  List<TodayCareReminder>? care,
  Future<void> Function(DayOccurrence)? onTaken,
  Future<void> Function(DayOccurrence)? onSnooze,
  Future<void> Function(TodayCareReminder)? onDone,
  ValueChanged<TodayCareReminder>? onEdit,
}) => TodayAgenda(
  now: _now,
  occurrences: doses ?? [_dose()],
  care: care ?? [],
  onAdd: () {},
  onTaken: onTaken ?? (_) async {},
  onSnooze: onSnooze ?? (_) async {},
  onHistory: (_) {},
  onEditCare: onEdit ?? (_) {},
  onCompleteCare: onDone ?? (_) async {},
);

void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(390, 844),
    double scale = 1,
    bool dark = false,
    bool reducedMotion = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: (dark ? MedicynTheme.dark() : MedicynTheme.light()).copyWith(
          platform: TargetPlatform.android,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: reducedMotion,
          ),
          child: child!,
        ),
        home: child,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'one agenda merges care with doses and clears already taken items',
    (tester) async {
      await pump(
        tester,
        _agenda(
          doses: [
            _dose(name: 'Vitamin D', hour: 8, status: DayDoseStatus.taken),
            _dose(),
            _dose(
              name: 'Evening medicine',
              hour: 20,
              status: DayDoseStatus.upcoming,
            ),
          ],
          care: [
            _care(),
            _care(title: 'Completed scan', completed: true),
          ],
        ),
      );
      expect(find.textContaining('Vitamin D'), findsNothing);
      expect(find.text('Completed scan'), findsNothing);
      expect(find.text('Metformin 500 mg'), findsOneWidget);
      expect(find.text('3 remaining'), findsOneWidget);
      expect(find.text('2 of 5 done'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Blood test')).dy,
        greaterThan(tester.getTopLeft(find.text('Metformin 500 mg')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Evening medicine 500 mg')).dy,
        greaterThan(tester.getTopLeft(find.text('Blood test')).dy),
      );
      expect(find.byType(Dismissible), findsNothing);
      expect(find.byType(DoseCalendar), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'marking taken clears only that occurrence, retaining the later dose',
    (tester) async {
      var taken = false;
      DayOccurrence? answered;
      await pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) => _agenda(
            doses: [
              _dose(
                status: taken ? DayDoseStatus.taken : DayDoseStatus.pending,
              ),
              _dose(hour: 20, status: DayDoseStatus.upcoming),
            ],
            onTaken: (dose) async {
              answered = dose;
              setState(() => taken = true);
            },
          ),
        ),
      );
      expect(find.text('Metformin 500 mg'), findsNWidgets(2));
      await tester.tap(find.text('Taken').first);
      await tester.pumpAndSettle();
      expect(answered?.scheduledAt.hour, 9);
      expect(find.text('Metformin 500 mg'), findsOneWidget);
      expect(find.text('1 remaining'), findsOneWidget);
      expect(find.text('1 of 2 done'), findsOneWidget);
    },
  );

  testWidgets(
    'snooze stays accessible and a failed action leaves the dose visible',
    (tester) async {
      var snoozed = false;
      await pump(
        tester,
        _agenda(
          onTaken: (_) async => throw StateError('write failed'),
          onSnooze: (_) async => snoozed = true,
        ),
      );
      await tester.tap(find.text('Snooze'));
      await tester.pumpAndSettle();
      expect(snoozed, isTrue);
      await tester.tap(find.text('Taken'));
      await tester.pumpAndSettle();
      expect(find.text('Metformin 500 mg'), findsOneWidget);
      expect(find.textContaining('Could not save this change'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('repeat taps cannot submit an action twice while saving', (
    tester,
  ) async {
    final result = Completer<void>();
    var calls = 0;
    await pump(
      tester,
      _agenda(
        onTaken: (_) {
          calls++;
          return result.future;
        },
      ),
    );
    await tester.tap(find.text('Taken'));
    await tester.pump();
    await tester.tap(find.text('Taken'));
    expect(calls, 1);
    result.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('all done and empty are distinct, and future care is reachable', (
    tester,
  ) async {
    await pump(tester, _agenda(doses: []));
    // Copy for the "nothing scheduled" state rotates by day-of-month; _now
    // is the 5th, so index 5 % 4 == 1.
    expect(find.text('A quiet start today'), findsOneWidget);
    await pump(
      tester,
      _agenda(
        doses: [_dose(status: DayDoseStatus.taken)],
        care: [_care(day: 6)],
      ),
    );
    expect(find.text('All clear for today'), findsOneWidget);
    expect(find.text('COMING UP'), findsOneWidget);
    expect(find.text('Blood test'), findsOneWidget);
    expect(
      find.text('Done'),
      findsNothing,
      reason: 'future care cannot be completed by accident',
    );
  });

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(640, 960),
  ]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('agenda fits ${size.width} at $scale text scale', (
        tester,
      ) async {
        await pump(
          tester,
          _agenda(
            doses: [
              _dose(name: 'A medicine with a longer name'),
              _dose(hour: 20, status: DayDoseStatus.snoozed),
            ],
            care: [
              _care(
                title: 'A longer physiotherapy appointment',
                kind: 'therapy',
              ),
              _care(day: 6, title: 'MRI scan', kind: 'scan'),
            ],
          ),
          size: size,
          scale: scale,
          dark: scale == 1.5,
          reducedMotion: scale == 1.5,
        );
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'care editor validates, saves selected category, and keeps fields on failure',
    (tester) async {
      TodayCareReminder? saved;
      var fail = true;
      await pump(
        tester,
        Scaffold(
          body: TodayCareEditor(
            kind: TodayCareKind.scan,
            onSave: (reminder) async {
              if (fail) throw StateError('offline disk failure');
              saved = reminder;
            },
          ),
        ),
      );
      await tester.ensureVisible(find.text('Add reminder'));
      await tester.tap(find.text('Add reminder'));
      await tester.pumpAndSettle();
      expect(find.text('Add a name for your reminder.'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, 'Knee MRI');
      await tester.ensureVisible(find.text('Add reminder'));
      await tester.tap(find.text('Add reminder'));
      await tester.pumpAndSettle();
      expect(find.text('Could not save. Please try again.'), findsOneWidget);
      expect(find.text('Knee MRI'), findsOneWidget);
      fail = false;
      await tester.ensureVisible(find.text('Add reminder'));
      await tester.tap(find.text('Add reminder'));
      await tester.pumpAndSettle();
      expect(saved?.title, 'Knee MRI');
      expect(saved?.kind, 'scan');
      expect(saved?.reminderMinutes, 30);
    },
  );

  testWidgets(
    'care form fits small phones with large text and the keyboard open',
    (tester) async {
      await pump(
        tester,
        Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 568),
              viewInsets: EdgeInsets.only(bottom: 260),
              textScaler: TextScaler.linear(1.5),
            ),
            child: TodayCareEditor(
              kind: TodayCareKind.therapy,
              onSave: (_) async {},
            ),
          ),
        ),
        size: const Size(320, 568),
        scale: 1.5,
      );
      await tester.ensureVisible(find.text('Add reminder'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Today visual review', (tester) async {
    if (!const bool.fromEnvironment('TODAY_PREVIEW')) return;
    final font = FontLoader('Public Sans')
      ..addFont(rootBundle.load('assets/fonts/PublicSans-Variable.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final boundary = GlobalKey();
    await pump(
      tester,
      RepaintBoundary(
        key: boundary,
        child: Scaffold(
          body: _agenda(
            doses: [
              _dose(name: 'Vitamin D', hour: 8, status: DayDoseStatus.taken),
              _dose(),
              _dose(
                name: 'Magnesium',
                hour: 20,
                status: DayDoseStatus.upcoming,
              ),
            ],
            care: [
              _care(),
              _care(title: 'Physiotherapy', day: 7, kind: 'therapy'),
            ],
          ),
          bottomNavigationBar: MedicynBottomNav(index: 0, onChanged: (_) {}),
        ),
      ),
    );
    await tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '/private/tmp/medicyn-today-review.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });
}
