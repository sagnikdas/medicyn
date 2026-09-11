import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_settings.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../core/widgets/medicyn_motion.dart';
import '../../data/local/database.dart';
import '../../data/local/lifecycle.dart';
import '../../data/local/tables.dart';
import '../notification_engine/notification_actions.dart';
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
    return MedicynPressable(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
              boxShadow: MedicynTheme.ambientShadow,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.1),
                    ),
                    child: Icon(
                      Icons.medication,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
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
                          Text(
                            medicine.doseAmount,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        const SizedBox(height: 4),
                        Text(
                          describeSchedule(item.schedule),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        _LifecycleStatus(schedule: item.schedule),
                        if (reminderStatus(item.schedule) ==
                            ReminderStatus.asNeeded)
                          _LogNowAction(db: db, scheduleId: item.schedule.id),
                        _RefillStatus(db: db, item: item),
                        if (attribution != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            attribution!,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        _SnoozeStatus(
                          db: db,
                          scheduleId: item.schedule.id,
                          scheduleUpdatedAt: item.schedule.updatedAt,
                        ),
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
        ),
      ),
    );
  }
}

class _LifecycleStatus extends StatelessWidget {
  const _LifecycleStatus({required this.schedule});
  final Schedule schedule;

  @override
  Widget build(BuildContext context) {
    final status = reminderStatus(schedule);
    // `describeSchedule` already communicates an as-needed frequency. It is
    // not a second lifecycle line, and repeating it here made every PRN
    // reminder read "As needed" twice in Plan.
    if (status == ReminderStatus.active || status == ReminderStatus.asNeeded) {
      return const SizedBox.shrink();
    }
    final label = switch (status) {
      ReminderStatus.paused =>
        schedule.pauseUntil == null
            ? 'Paused'
            : 'Paused until ${_format(schedule.pauseUntil!)}',
      ReminderStatus.completed => 'Completed',
      ReminderStatus.active => '',
      ReminderStatus.asNeeded => '',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.tertiary,
        ),
      ),
    );
  }

  String _format(DateTime value) {
    final local = value.toLocal();
    return '${local.day}/${local.month}/${local.year}';
  }
}

/// The action an as-needed (PRN) medicine gets instead of a due time: there
/// is nothing on the calendar to answer, so this is the only way one of
/// these ever reaches dose history. Tapping it logs Taken for right now,
/// through the exact same [recordAsNeededDoseTaken] -> [recordDoseTaken] ->
/// `dose_logs` path a scheduled reminder's own Taken button uses, so it
/// shows up identically in History, Insights and exports.
class _LogNowAction extends StatefulWidget {
  const _LogNowAction({required this.db, required this.scheduleId});
  final AppDatabase db;
  final String scheduleId;

  @override
  State<_LogNowAction> createState() => _LogNowActionState();
}

class _LogNowActionState extends State<_LogNowAction> {
  bool _busy = false;

  Future<void> _logNow() async {
    if (_busy) return;
    setState(() => _busy = true);
    MedicynMotion.confirm(context);
    try {
      await recordAsNeededDoseTaken(widget.db, scheduleId: widget.scheduleId);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Logged as taken')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _busy ? null : _logNow,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_circle_outline, size: 18),
          label: const Text('Log now'),
        ),
      ),
    );
  }
}

/// Returns the expiry of an active snooze, or null when the latest log is not
/// a snooze or its configured window has elapsed.
DateTime? activeSnoozeUntil({
  required String? action,
  required DateTime? loggedAt,
  required DateTime scheduleUpdatedAt,
  required Duration snoozeWindow,
  required DateTime now,
}) {
  if (action != DoseAction.snoozed.name ||
      loggedAt == null ||
      loggedAt.isBefore(scheduleUpdatedAt)) {
    return null;
  }
  final candidate = loggedAt.add(snoozeWindow);
  return candidate.isAfter(now) ? candidate : null;
}

/// Shows "Snoozed until HH:mm" under a reminder while its most recent dose
/// log is an active snooze for the configured duration. A snooze from before
/// the reminder was edited is ignored: the edit starts a new reminder version.
///
/// Polls rather than watches: the notification engine records Taken/Snooze
/// through its own `AppDatabase` instance — often from a background isolate
/// when the user snoozes straight from the notification tray — and those
/// writes don't push to a `.watch()` stream on a different instance. See
/// [AppDatabase.latestDoseLogOnce].
class _SnoozeStatus extends StatefulWidget {
  const _SnoozeStatus({
    required this.db,
    required this.scheduleId,
    required this.scheduleUpdatedAt,
  });
  final AppDatabase db;
  final String scheduleId;
  final DateTime scheduleUpdatedAt;

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
    AppSettings.instance.addListener(_onSettingsChanged);
    _tick();
  }

  @override
  void dispose() {
    AppSettings.instance.removeListener(_onSettingsChanged);
    _poll?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _SnoozeStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scheduleId != widget.scheduleId ||
        oldWidget.scheduleUpdatedAt != widget.scheduleUpdatedAt) {
      // A local or remote reminder edit can invalidate the old snooze while
      // this state object is reused by the list. Do not wait for the poller
      // to notice that the card now represents a new schedule version.
      unawaited(_refresh());
    }
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    // A newly selected duration must update an already-visible Plan card
    // immediately instead of waiting for the next polling tick.
    unawaited(_refresh());
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
    final until = activeSnoozeUntil(
      action: log?.action,
      loggedAt: log?.loggedAt,
      scheduleUpdatedAt: widget.scheduleUpdatedAt,
      snoozeWindow: Duration(minutes: AppSettings.instance.snoozeMinutes),
      now: DateTime.now(),
    );
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
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// Shows the low-refill warning under a reminder, or nothing when the bottle
/// isn't tracked or isn't low.
///
/// A one-shot query per build rather than a `.watch()` stream, for the same
/// reason as [_SnoozeStatus]: a Taken recorded from the notification tray
/// runs on a separate `AppDatabase` instance and never pushes to this one's
/// streams. HomeScreen's own 15-second clock already rebuilds this card,
/// which keeps the count close enough to live without a poll timer of its
/// own.
class _RefillStatus extends StatelessWidget {
  const _RefillStatus({required this.db, required this.item});
  final AppDatabase db;
  final ScheduleWithMedicine item;

  @override
  Widget build(BuildContext context) {
    if (item.medicine.tabletsRemaining == null) return const SizedBox.shrink();
    return FutureBuilder<int>(
      future: db.takenCountSince(item.schedule.id, item.medicine.updatedAt),
      builder: (context, snapshot) {
        final warning = refillWarningLine(
          refillDaysLeft(
            tabletsRemaining: derivedTabletsRemaining(
              item.medicine,
              snapshot.data ?? 0,
            ),
            tabletsPerDose: item.medicine.tabletsPerDose,
            schedules: [item.schedule],
          ),
        );
        if (warning == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            warning,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        );
      },
    );
  }
}
