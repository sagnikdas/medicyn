import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicyn/data/local/database.dart';
import 'package:medicyn/data/local/tables.dart';
import 'package:medicyn/features/reminders_home/medicines_list_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_supabase.dart';

/// The list used to be a plain `ListView` fed straight from the schedules
/// stream: a delete or an add just snapped the widget tree to the new
/// length. It is now a manually-diffed `SliverAnimatedList` — this test
/// exists because that diff is the one part of this screen that can crash
/// outright (a miscounted index desyncs the animated list) if it is wrong,
/// not just look worse.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await initFakeSupabase(backend: FakePostgrest(), userId: 'test-user');
  });

  Future<void> addMedicine(String id, String name) async {
    await db.upsertMedicine(
      MedicinesCompanion.insert(id: id, drugName: name),
    );
    await db.upsertSchedule(
      SchedulesCompanion.insert(
        id: 'sched-$id',
        medicineId: id,
        frequencyType: FrequencyType.daily.name,
        times: const ['08:00'],
      ),
    );
  }

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Widget harness() => MaterialApp(
    home: MedicinesListScreen(
      db: db,
      names: const {},
      onAdd: () {},
      onEdit: (_) async {},
      onDelete: (item) => db.deleteMedicineAndHistory(
        item.medicine.id,
        by: 'test-user',
      ),
    ),
  );

  // `testWidgets` does not unmount the previously-pumped tree on its own —
  // it just persists until the next pumpWidget. Without this, the screen's
  // `dispose()` (which cancels its stream subscription) never runs, and a
  // descendant's own timer (ReminderCard's `_SnoozeStatus` poll) is still
  // pending when the framework checks for leaks at test end, failing every
  // test in this file regardless of the diff logic under test.
  Future<void> disposeTree(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox());

  testWidgets('shows every medicine from the stream', (tester) async {
    await addMedicine('m1', 'Metformin');
    await addMedicine('m2', 'Lisinopril');

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('Metformin'), findsOneWidget);
    expect(find.text('Lisinopril'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('deleting one card animates it out without disturbing the others', (
    tester,
  ) async {
    await addMedicine('m1', 'Metformin');
    await addMedicine('m2', 'Lisinopril');
    await addMedicine('m3', 'Atorvastatin');

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await db.deleteMedicineAndHistory('m2', by: 'test-user');
    // Mid-animation: nothing should have thrown, and the removed card is on
    // its way out rather than already gone or duplicated.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 140));
    await tester.pumpAndSettle();

    expect(find.text('Metformin'), findsOneWidget);
    expect(find.text('Lisinopril'), findsNothing);
    expect(find.text('Atorvastatin'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('adding a card while others are present inserts it in place', (
    tester,
  ) async {
    await addMedicine('m1', 'Metformin');

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await addMedicine('m2', 'Lisinopril');
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Metformin'), findsOneWidget);
    expect(find.text('Lisinopril'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets(
    'deleting the last medicine waits for its exit animation before showing the empty state',
    (tester) async {
      await addMedicine('m1', 'Metformin');

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      await db.deleteMedicineAndHistory('m1', by: 'test-user');
      await tester.pump();
      // Still mid-exit-animation: the empty state must not have swapped in
      // yet (that swap would tear down the animated list mid-flight).
      expect(find.text('No reminders yet'), findsNothing);

      await tester.pumpAndSettle();
      expect(find.text('No reminders yet'), findsOneWidget);
      expect(find.text('Metformin'), findsNothing);
      await disposeTree(tester);
    },
  );

  testWidgets('rapid successive deletes do not crash the animated list', (
    tester,
  ) async {
    await addMedicine('m1', 'Metformin');
    await addMedicine('m2', 'Lisinopril');
    await addMedicine('m3', 'Atorvastatin');

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await db.deleteMedicineAndHistory('m1', by: 'test-user');
    await tester.pump(const Duration(milliseconds: 20));
    await db.deleteMedicineAndHistory('m3', by: 'test-user');
    await tester.pump(const Duration(milliseconds: 20));

    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Lisinopril'), findsOneWidget);
    expect(find.text('Metformin'), findsNothing);
    expect(find.text('Atorvastatin'), findsNothing);
    await disposeTree(tester);
  });
}
