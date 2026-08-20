import 'package:flutter/material.dart';

import 'care_service.dart';
import 'edit_attribution.dart';

/// Whether the patient's phone can actually ring. Shown to both sides of a
/// link so the parent sees the same panel the caregiver is judging them by.
class SetupHealthPanel extends StatelessWidget {
  const SetupHealthPanel({super.key, required this.profile, required this.viewingOwnData});

  final CareProfile? profile;
  final bool viewingOwnData;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final who = viewingOwnData ? 'this phone' : (profile?.displayName ?? 'their phone');
    final warn = profile?.remindersMayNotFire == true;
    final silent = _looksSilent(profile?.lastSeenAt);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Can reminders fire?', style: text.titleSmall),
        const SizedBox(height: 4),
        Text(
          viewingOwnData
              ? 'What your family member sees about whether alarms can ring on $who.'
              : 'If any of these is off, reminders on $who may never fire — '
                  'and you would not hear about missed doses either.',
          style: text.bodySmall,
        ),
        const SizedBox(height: 12),
        if (warn)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  viewingOwnData
                      ? 'Reminders may not fire until notifications, exact alarms, '
                          'and battery exemption are allowed, and at least one alarm is armed.'
                      : 'Reminders may not be firing on their phone.',
                  style: text.bodySmall?.copyWith(color: scheme.onErrorContainer),
                ),
              ),
            ),
          ),
        if (silent)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  viewingOwnData
                      ? 'This phone has not checked in for a day. Open Dosely so your family knows it is still on.'
                      : 'Their phone has not checked in since yesterday. That is not a missed dose — the app did not run.',
                  style: text.bodySmall?.copyWith(color: scheme.onErrorContainer),
                ),
              ),
            ),
          ),
        _row(context, 'Notifications allowed', describeHealthFlag(profile?.notificationsAllowed)),
        _row(context, 'Exact alarms allowed', describeHealthFlag(profile?.exactAlarmsAllowed)),
        _row(context, 'Battery exemption', describeHealthFlag(profile?.batteryExemption)),
        _row(
          context,
          'Alarms armed',
          profile?.armedAlarmCount == null ? 'Not reported yet' : '${profile!.armedAlarmCount}',
        ),
        _row(context, 'Last check-in', describeLastSeen(profile?.lastSeenAt)),
      ],
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

bool _looksSilent(DateTime? lastSeenAt, {DateTime? now}) {
  if (lastSeenAt == null) return false;
  return (now ?? DateTime.now()).difference(lastSeenAt) >= const Duration(hours: 24);
}
