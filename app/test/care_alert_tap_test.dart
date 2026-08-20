import 'package:dosely/features/push/push_events.dart';
import 'package:dosely/features/push/push_handlers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('careAlertPatientIdFromData', () {
    test('returns the patient on a missed-dose tap', () {
      expect(
        careAlertPatientIdFromData({
          pushEventKey: pushEventMissedDose,
          pushPatientIdKey: 'patient-1',
        }),
        'patient-1',
      );
    });

    test(
      'ignores a silent data-changed message — that tap has no feed to open',
      () {
        expect(
          careAlertPatientIdFromData({
            pushEventKey: pushEventDataChanged,
            pushPatientIdKey: 'patient-1',
          }),
          isNull,
        );
      },
    );

    test(
      'ignores a missed-dose message with no patient — opening a feed needs one',
      () {
        expect(
          careAlertPatientIdFromData({pushEventKey: pushEventMissedDose}),
          isNull,
        );
        expect(
          careAlertPatientIdFromData({
            pushEventKey: pushEventMissedDose,
            pushPatientIdKey: '',
          }),
          isNull,
        );
      },
    );
  });
}
