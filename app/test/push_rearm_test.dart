import 'package:dosely/features/push/push_events.dart';
import 'package:flutter_test/flutter_test.dart';

/// A visible data_changed ping is for the caregiver. Pulling it would write
/// the patient's medicines into the caregiver's encrypted per-account file.
void main() {
  test('a silent re-arm from the caregiver is pulled', () {
    expect(
      shouldPullAndRearm(
        event: pushEventDataChanged,
        rearm: pushRearmYes,
        hasNotification: false,
      ),
      isTrue,
    );
  });

  test('a visible ping to the caregiver is not pulled', () {
    expect(
      shouldPullAndRearm(
        event: pushEventDataChanged,
        rearm: pushRearmNo,
        hasNotification: true,
      ),
      isFalse,
    );
  });

  test('a notification block alone is enough to refuse the pull', () {
    // Defence in depth: even if `rearm` were omitted or forged true, a
    // visible message must not land in this device's local database.
    expect(
      shouldPullAndRearm(
        event: pushEventDataChanged,
        rearm: pushRearmYes,
        hasNotification: true,
      ),
      isFalse,
    );
  });

  test('a legacy silent message with no rearm key still pulls', () {
    expect(
      shouldPullAndRearm(
        event: pushEventDataChanged,
        rearm: null,
        hasNotification: false,
      ),
      isTrue,
    );
  });

  test('a missed-dose alert is never a re-arm', () {
    expect(
      shouldPullAndRearm(
        event: pushEventMissedDose,
        rearm: null,
        hasNotification: true,
      ),
      isFalse,
    );
  });
}
