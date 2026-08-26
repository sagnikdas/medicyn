import 'package:dosely/core/theme.dart';
import 'package:dosely/data/local/database.dart';
import 'package:dosely/features/insights/insights_screen.dart';
import 'package:dosely/features/settings/settings_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_supabase.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await initFakeSupabase(backend: FakePostgrest(), userId: 'user-1');
  });
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> pumpTab(WidgetTester tester, {required Widget child}) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(theme: DoselyTheme.light(), home: child),
    );
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('Insights resets its list when the tab becomes active', (
    tester,
  ) async {
    await pumpTab(tester, child: InsightsScreen(db: db, active: false));
    final list = find.byType(ListView);
    await tester.drag(list, const Offset(0, -500));
    await tester.pump();
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    expect(position.pixels, greaterThan(0));

    await pumpTab(tester, child: InsightsScreen(db: db, active: true));
    expect(position.pixels, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('Profile resets its list when the tab becomes active', (
    tester,
  ) async {
    await pumpTab(
      tester,
      child: SettingsScreen(db: db, embedded: true, active: false),
    );
    final list = find.byType(ListView);
    await tester.drag(list, const Offset(0, -500));
    await tester.pump();
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    expect(position.pixels, greaterThan(0));

    await pumpTab(
      tester,
      child: SettingsScreen(db: db, embedded: true, active: true),
    );
    expect(position.pixels, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
