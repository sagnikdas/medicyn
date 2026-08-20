/// Whether this phone can actually ring — the snapshot synced onto the
/// owner's profile so a caregiver is not left reading "no alerts" as "all
/// is well" when notifications, exact alarms, or the battery exemption are
/// off.
class DeviceHealthSnapshot {
  const DeviceHealthSnapshot({
    required this.notificationsAllowed,
    required this.exactAlarmsAllowed,
    required this.batteryExemption,
    required this.armedAlarmCount,
    required this.checkedAt,
  });

  final bool notificationsAllowed;
  final bool exactAlarmsAllowed;
  final bool batteryExemption;
  final int armedAlarmCount;
  final DateTime checkedAt;

  bool get remindersMayNotFire =>
      !notificationsAllowed || !exactAlarmsAllowed || !batteryExemption || armedAlarmCount == 0;
}
