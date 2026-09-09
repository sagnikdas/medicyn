import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicyn/core/app_settings.dart';
import 'package:medicyn/data/local/database.dart';
import 'package:medicyn/features/review_edit/review_edit_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_supabase.dart';

/// Regression guard for extracting the medicine-fields block out of this
/// screen into `MedicineFieldsForm` (`medicine_fields_form.dart`), reused by
/// the multi-item prescription review screen. The extraction rewired every
/// callback (frequency selection, day toggling, interval validation) from
/// direct `setState` calls to widget callbacks -- this is the seam a mis-
/// wired callback would show up on, not the extraction's mechanical parts.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await initFakeSupabase(backend: FakePostgrest(), userId: 'test-user');
  });

  setUp(() async {
    AppSettings.instance.resetForTest();
    await AppSettings.instance.init();
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
    AppSettings.instance.resetForTest();
  });

  Widget harness() =>
      MaterialApp(home: ReviewEditScreen(db: db));

  testWidgets('Save stays disabled until a drug name is entered', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    FilledButton saveButton() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save reminder'));

    expect(saveButton().onPressed, isNull);

    // Daily (the default frequency) also requires at least one time, which
    // this test is not exercising -- switch to "As needed" so the drug name
    // is the only thing gating Save here.
    await tester.tap(find.widgetWithText(ChoiceChip, 'As needed'));
    await tester.pumpAndSettle();
    expect(saveButton().onPressed, isNull);

    await tester.enterText(find.widgetWithText(TextField, 'Medicine name *'), 'Metformin');
    await tester.pump();

    expect(saveButton().onPressed, isNotNull);
  });

  testWidgets('selecting "Some days" reveals day chips wired to the frequency change', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('Mon'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Some days'));
    await tester.pumpAndSettle();

    expect(find.text('Mon'), findsOneWidget);
    expect(find.text('Sun'), findsOneWidget);
    final monChip = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, 'Mon'),
    );
    expect(monChip.selected, isFalse);

    // Times section stays visible for "Some days" too, not just Daily.
    expect(find.text('Add time'), findsOneWidget);
  });

  testWidgets('selecting "Every X hrs" reveals the interval field with validation wired through', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Medicine name *'), 'Metformin');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Every X hrs'));
    await tester.pumpAndSettle();

    final intervalField = find.widgetWithText(TextField, 'Every how many hours?');
    expect(intervalField, findsOneWidget);

    FilledButton saveButton() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save reminder'));

    // 0 is out of range -- the field must show the error and Save must
    // gate on it, the same as before the extraction (a time is also
    // required for this frequency, so Save was already disabled before
    // typing 0; the point here is that the error text itself appears).
    await tester.enterText(intervalField, '0');
    await tester.pump();
    expect(find.text('Must be between 1 and 24 hours'), findsOneWidget);
    expect(saveButton().onPressed, isNull);

    await tester.enterText(intervalField, '8');
    await tester.pump();
    expect(find.text('Must be between 1 and 24 hours'), findsNothing);
  });

  testWidgets('"As needed" hides the times section entirely', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Medicine name *'), 'Metformin');
    await tester.tap(find.widgetWithText(ChoiceChip, 'As needed'));
    await tester.pumpAndSettle();

    expect(find.text('Add time'), findsNothing);

    FilledButton saveButton() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save reminder'));
    // No times required for as-needed.
    expect(saveButton().onPressed, isNotNull);
  });
}
