import 'package:dosely/data/local/database.dart';
import 'package:dosely/features/care/reminder_attribution.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Medicine medicine({
    DateTime? updatedAt,
    String? updatedBy,
  }) =>
      Medicine(
        id: 'med-1',
        drugName: 'Metformin',
        strength: '500mg',
        form: 'tablet',
        doseAmount: '1 tablet',
        notes: '',
        createdAt: DateTime(2026, 8, 1),
        updatedAt: updatedAt ?? DateTime(2026, 8, 18, 9),
        updatedBy: updatedBy,
        pendingSync: false,
        deleted: false,
      );

  Schedule schedule({
    DateTime? updatedAt,
    String? updatedBy,
  }) =>
      Schedule(
        id: 'sch-1',
        medicineId: 'med-1',
        frequencyType: 'daily',
        times: const ['08:00'],
        daysOfWeek: const [],
        intervalHours: null,
        active: true,
        createdAt: DateTime(2026, 8, 1),
        updatedAt: updatedAt ?? DateTime(2026, 8, 18, 9),
        updatedBy: updatedBy,
        pendingSync: false,
        deleted: false,
      );

  group('latestReminderChange', () {
    test('quotes the schedule when it is newer', () {
      final change = latestReminderChange(
        medicine(updatedAt: DateTime(2026, 8, 18, 9), updatedBy: 'parent'),
        schedule(updatedAt: DateTime(2026, 8, 18, 10), updatedBy: 'child'),
      );
      expect(change.updatedBy, 'child');
      expect(change.updatedAt, DateTime(2026, 8, 18, 10));
    });

    test('quotes the medicine when it is newer or tied', () {
      final at = DateTime(2026, 8, 18, 9);
      final change = latestReminderChange(
        medicine(updatedAt: at, updatedBy: 'child'),
        schedule(updatedAt: at, updatedBy: 'parent'),
      );
      expect(change.updatedBy, 'child');
    });
  });

  group('reminderChangedByLine', () {
    final tuesday = DateTime(2026, 8, 18, 15, 0); // a Tuesday

    test('is silent when the owner last wrote', () {
      expect(
        reminderChangedByLine(
          ownerUserId: 'parent',
          updatedBy: 'parent',
          updatedAt: tuesday,
          actorDisplayName: 'Amma',
        ),
        isNull,
      );
    });

    test('is silent when nobody is recorded as the writer', () {
      expect(
        reminderChangedByLine(
          ownerUserId: 'parent',
          updatedBy: null,
          updatedAt: tuesday,
          actorDisplayName: 'Priya',
        ),
        isNull,
      );
    });

    test('names the other person and the weekday', () {
      expect(
        reminderChangedByLine(
          ownerUserId: 'parent',
          updatedBy: 'child',
          updatedAt: tuesday,
          actorDisplayName: 'Priya',
        ),
        'Changed by Priya, Tuesday',
      );
    });

    test('does not invent a name when the profile is missing', () {
      expect(
        reminderChangedByLine(
          ownerUserId: 'parent',
          updatedBy: 'child',
          updatedAt: tuesday,
          actorDisplayName: null,
        ),
        'Changed by a family member, Tuesday',
      );
    });
  });
}
