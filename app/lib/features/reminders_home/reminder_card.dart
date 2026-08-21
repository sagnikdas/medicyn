import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/local/database.dart';
import '../../data/local/tables.dart';
import 'refill.dart';
import 'reminder_copy.dart';

class ReminderCard extends StatelessWidget {
  const ReminderCard({
    super.key,
    required this.item,
    required this.db,
    required this.onTap,
    required this.onDelete,
    this.attribution,
  });
  final ScheduleWithMedicine item;
  final AppDatabase db;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final String? attribution;

  @override
  Widget build(BuildContext context) {
    final medicine = item.medicine;
    final title = medicineTitle(medicine);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    if (medicine.doseAmount.isNotEmpty)
                      Text(medicine.doseAmount, style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 4),
                    Text(describeSchedule(item.schedule), style: Theme.of(context).textTheme.bodySmall),
                    if (refillWarningLine(refillDaysLeft(
                          tabletsRemaining: medicine.tabletsRemaining,
                          tabletsPerDose: medicine.tabletsPerDose,
                          schedules: [item.schedule],
                        ))
                        case final warning?) ...[
                      const SizedBox(height: 4),
                      Text(
                        warning,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    if (attribution != null) ...[
                      const SizedBox(height: 4),
                      Text(attribution!, style: Theme.of(context).textTheme.bodySmall),
                    ],
                    _SnoozeStatus(db: db, scheduleId: item.schedule.id),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Stop or delete',
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows "Snoozed until HH:mm" under a reminder while its most recent dose
/// log is an active (< 10 minutes old) snooze, then disappears on its own.
///
/// Polls rather than watches: the notification engine records Taken/Snooze
/// through its own `AppDatabase` instance — often from a background isolate
/// when the user snoozes straight from the notification tray — and those
/// writes don't push to a `.watch()` stream on a different instance. See
/// [AppDatabase.latestDoseLogOnce].
class _SnoozeStatus extends StatefulWidget {
  const _SnoozeStatus({required this.db, required this.scheduleId});
  final AppDatabase db;
  final String scheduleId;

  @override
  State<_SnoozeStatus> createState() => _SnoozeStatusState();
}

class _SnoozeStatusState extends State<_SnoozeStatus> {
  /// While a snooze is on screen the countdown has to expire promptly, so it
  /// is checked often. The rest of the time — which is almost all of the
  /// time, for almost every card — a slower beat is enough to notice a
  /// snooze made from the notification tray. The old fixed 15s ran per
  /// visible card for as long as the app was open, so a list of eight
  /// reminders meant ~32 database reads a minute to display nothing.
  static const _activePollInterval = Duration(seconds: 15);
  static const _idlePollInterval = Duration(minutes: 1);

  Timer? _poll;
  DateTime? _snoozedUntil;

  @override
  void initState() {
    super.initState();
    _tick();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _tick() async {
    await _refresh();
    if (!mounted) return;
    _poll = Timer(
      _snoozedUntil == null ? _idlePollInterval : _activePollInterval,
      _tick,
    );
  }

  Future<void> _refresh() async {
    final log = await widget.db.latestDoseLogOnce(widget.scheduleId);
    if (!mounted) return;
    DateTime? until;
    if (log != null && log.action == DoseAction.snoozed.name) {
      final candidate = log.loggedAt.add(const Duration(minutes: 10));
      if (candidate.isAfter(DateTime.now())) until = candidate;
    }
    if (until != _snoozedUntil) setState(() => _snoozedUntil = until);
  }

  @override
  Widget build(BuildContext context) {
    final until = _snoozedUntil;
    if (until == null) return const SizedBox.shrink();
    final local = until.toLocal();
    final label =
        'Snoozed until ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    final color = Theme.of(context).colorScheme.tertiary;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.snooze, size: 15, color: color),
          const SizedBox(width: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color)),
        ],
      ),
    );
  }
}
