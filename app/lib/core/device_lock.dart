/// How long the app can sit in the background before coming back requires
/// the phone's PIN / pattern / biometric. Two minutes is long enough to
/// take a call or check a message without a second unlock, and short
/// enough that a phone left on a table does not stay open.
const kDeviceLockGrace = Duration(minutes: 2);

/// Whether resuming after [pausedAt] should cover the UI until the device
/// credential succeeds.
///
/// A phone with no screen lock cannot satisfy this, and prompting would
/// fail in a loop — so [deviceProtected] false never locks. Cold start
/// ([pausedAt] null) also does not: the user already unlocked the phone
/// to open the app.
bool shouldLockOnResume({
  required DateTime? pausedAt,
  required DateTime now,
  required bool deviceProtected,
  Duration grace = kDeviceLockGrace,
}) {
  if (!deviceProtected) return false;
  if (pausedAt == null) return false;
  return !now.difference(pausedAt).isNegative &&
      now.difference(pausedAt) >= grace;
}
