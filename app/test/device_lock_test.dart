import 'package:medicyn/core/device_lock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final paused = DateTime(2026, 8, 20, 12, 0);

  test('does not lock on a cold start', () {
    expect(
      shouldLockOnResume(pausedAt: null, now: paused, deviceProtected: true),
      isFalse,
    );
  });

  test('does not lock when the phone has no screen lock', () {
    expect(
      shouldLockOnResume(
        pausedAt: paused,
        now: paused.add(kDeviceLockGrace),
        deviceProtected: false,
      ),
      isFalse,
    );
  });

  test('does not lock if the user was only away briefly', () {
    expect(
      shouldLockOnResume(
        pausedAt: paused,
        now: paused.add(const Duration(seconds: 30)),
        deviceProtected: true,
      ),
      isFalse,
    );
  });

  test('locks after the grace period on a protected device', () {
    expect(
      shouldLockOnResume(
        pausedAt: paused,
        now: paused.add(kDeviceLockGrace),
        deviceProtected: true,
      ),
      isTrue,
    );
  });

  test('locks when they have been away longer than the grace period', () {
    expect(
      shouldLockOnResume(
        pausedAt: paused,
        now: paused.add(kDeviceLockGrace + const Duration(minutes: 1)),
        deviceProtected: true,
      ),
      isTrue,
    );
  });
}
