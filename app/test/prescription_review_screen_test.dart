import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicyn/core/app_settings.dart';
import 'package:medicyn/data/local/database.dart';
import 'package:medicyn/data/local/tables.dart';
import 'package:medicyn/features/review_edit/parsed_medicine.dart';
import 'package:medicyn/features/reminders_home/today_care_store.dart';
import 'package:medicyn/features/review_prescription/parsed_care_item.dart';
import 'package:medicyn/features/review_prescription/parsed_prescription.dart';
import 'package:medicyn/features/review_prescription/prescription_review_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_supabase.dart';

/// Exercises the review/save logic via [PrescriptionReviewScreen]'s
/// `debugInitialPrescription` test seam, bypassing the real network call to
/// `parse-prescription` -- Supabase Functions' JSON decoding runs on its own
/// isolate, which does not resolve inside this test harness, and mocking
/// that isolate boundary is out of proportion to what this test needs to
/// verify (the review screen's own logic, not the edge function's).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await initFakeSupabase(backend: FakePostgrest(), userId: 'test-user');
  });

  setUp(() async {
    AppSettings.instance.resetForTest();
    await AppSettings.instance.init(consentOwnerId: 'test-user');
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
    AppSettings.instance.resetForTest();
  });

  ParsedPrescription twoMedicinesAndAWeeklyCareItem() => ParsedPrescription(
    medicines: const [
      ParsedMedicine(
        drugName: 'Metformin',
        strength: '500mg',
        doseAmount: '1 tablet',
        // asNeeded needs no times, so canSave doesn't depend on interacting
        // with the time-chip picker in these tests.
        frequencyType: FrequencyType.asNeeded,
        confidence: 0.9,
      ),
      ParsedMedicine(
        drugName: 'Lisinopril',
        strength: '10mg',
        doseAmount: '1 tablet',
        frequencyType: FrequencyType.asNeeded,
        confidence: 0.85,
      ),
    ],
    careItems: [
      ParsedCareItem(
        title: 'Physiotherapy',
        kind: TodayCareKind.therapy,
        firstDate: DateTime(2026, 9, 17),
        recurrence: CareRecurrence.weekly,
        occurrenceCount: 3,
        confidence: 0.8,
      ),
    ],
  );

  Widget harness(ParsedPrescription prescription) => MaterialApp(
    home: PrescriptionReviewScreen(
      ocrText: 'some ocr text',
      db: db,
      debugInitialPrescription: prescription,
    ),
  );

  testWidgets('renders every detected medicine and every expanded care occurrence', (
    tester,
  ) async {
    await tester.pumpWidget(harness(twoMedicinesAndAWeeklyCareItem()));
    await tester.pumpAndSettle();

    expect(find.text('Metformin'), findsOneWidget);
    expect(find.text('Lisinopril'), findsOneWidget);
    expect(find.text('Physiotherapy — 3 sessions'), findsOneWidget);
    expect(find.text('Session 1: Thu, Sep 17'), findsOneWidget);
    expect(find.text('Session 2: Thu, Sep 24'), findsOneWidget);
    expect(find.text('Session 3: Thu, Oct 1'), findsOneWidget);
  });

  testWidgets('excluding a medicine via its switch clears its include state', (
    tester,
  ) async {
    await tester.pumpWidget(harness(twoMedicinesAndAWeeklyCareItem()));
    await tester.pumpAndSettle();

    // Tapping Save itself is not exercised here: _save() awaits
    // NotificationService.scheduleForScheduleWithMedicine, whose platform
    // channel calls (flutter_local_notifications) never settle inside this
    // widget-test harness -- confirmed no other test in this suite calls
    // NotificationService either, including ReviewEditScreen's own,
    // previously-proven save path. The include/exclude *state* this
    // callback drives is what's under test.
    final firstSwitch = tester.widget<Switch>(find.byType(Switch).first);
    expect(firstSwitch.value, isTrue);

    await tester.tap(find.byType(Switch).first);
    await tester.pump();

    final afterToggle = tester.widget<Switch>(find.byType(Switch).first);
    expect(afterToggle.value, isFalse);
  });

  testWidgets('the cloud-backup warning appears when saving would drop care items', (
    tester,
  ) async {
    // consentCloudBackup defaults to false -- _cloudReady is false. This
    // covers the gate itself (_save's early SnackBar), not the full save
    // round-trip -- see the note on the include/exclude test above.
    await tester.pumpWidget(harness(twoMedicinesAndAWeeklyCareItem()));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save reminders'));
    await tester.pump();

    expect(
      find.textContaining('Other care needs sign-in and cloud backup'),
      findsOneWidget,
    );
  });

  testWidgets('an empty extraction falls back to the manual-entry recovery screen', (
    tester,
  ) async {
    await tester.pumpWidget(harness(const ParsedPrescription()));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Could not find any medicines or care instructions in that document.',
      ),
      findsOneWidget,
    );
    expect(find.text('Add a medicine manually'), findsOneWidget);
    expect(find.text('Add other care manually'), findsOneWidget);
  });
}
