import 'package:flutter/material.dart';

import '../../core/motion.dart';
import 'day_occurrences.dart';
import 'reminder_copy.dart';

/// Large Taken / Snooze cards for doses that are due, snoozed, or recent
/// enough that opening the app should be enough — the person does not
/// have to find the looping alarm in the system notification list.
class DoseAttentionPanel extends StatelessWidget {
  const DoseAttentionPanel({
    super.key,
    required this.occurrences,
    required this.now,
    required this.onMarkTaken,
    required this.onSnooze,
  });

  final List<DayOccurrence> occurrences;
  final DateTime now;
  final Future<void> Function(DayOccurrence occurrence) onMarkTaken;
  final Future<void> Function(DayOccurrence occurrence) onSnooze;

  @override
  Widget build(BuildContext context) {
    if (occurrences.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Time for your medicine',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Mark taken or snooze here. You do not have to find the alarm in your notifications.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < occurrences.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _AttentionCard(
            occurrence: occurrences[i],
            now: now,
            onMarkTaken: () => onMarkTaken(occurrences[i]),
            onSnooze: doseCanSnooze(occurrences[i].status)
                ? () => onSnooze(occurrences[i])
                : null,
          ),
        ],
      ],
    );
  }
}

class _AttentionCard extends StatefulWidget {
  const _AttentionCard({
    required this.occurrence,
    required this.now,
    required this.onMarkTaken,
    this.onSnooze,
  });

  final DayOccurrence occurrence;
  final DateTime now;
  final Future<void> Function() onMarkTaken;
  final Future<void> Function()? onSnooze;

  @override
  State<_AttentionCard> createState() => _AttentionCardState();
}

class _AttentionCardState extends State<_AttentionCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final medicine = widget.occurrence.item.medicine;
    final title = medicineTitle(medicine);
    final dose = medicine.doseAmount.trim();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x3300685F),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            attentionWhenLabel(widget.occurrence, widget.now),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onPrimaryContainer,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(color: scheme.onPrimary),
          ),
          if (dose.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Take $dose',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: scheme.inversePrimary),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy
                ? null
                : () {
                    DoselyMotion.confirm(context);
                    _run(widget.onMarkTaken);
                  },
            style: FilledButton.styleFrom(
              backgroundColor: scheme.onPrimary,
              foregroundColor: scheme.primary,
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('Mark as Taken'),
          ),
          if (widget.onSnooze != null) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : () => _run(widget.onSnooze!),
              style: OutlinedButton.styleFrom(
                foregroundColor: scheme.onPrimary,
                side: BorderSide(color: scheme.onPrimary),
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Snooze 10m'),
            ),
          ],
        ],
      ),
    );
  }
}

String attentionWhenLabel(DayOccurrence occurrence, DateTime now) {
  final local = occurrence.scheduledAt.toLocal();
  final time =
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  if (!isSameCalendarDay(occurrence.scheduledAt, now)) {
    return 'YESTERDAY · $time';
  }
  switch (occurrence.status) {
    case DayDoseStatus.pending:
      return 'DUE NOW · $time';
    case DayDoseStatus.snoozed:
      return 'SNOOZED · $time';
    case DayDoseStatus.missed:
      return 'EARLIER · $time';
    case DayDoseStatus.taken:
    case DayDoseStatus.upcoming:
    case DayDoseStatus.notRecorded:
      return time;
  }
}
