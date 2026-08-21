import 'package:flutter/material.dart';

import 'day_dose_style.dart';
import 'day_occurrences.dart';
import 'reminder_copy.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Quiet weekly count — facts only, no streak and no scolding.
class WeekAdherenceLine extends StatelessWidget {
  const WeekAdherenceLine({
    super.key,
    required this.taken,
    required this.expected,
  });

  final int taken;
  final int expected;

  @override
  Widget build(BuildContext context) {
    if (expected == 0) return const SizedBox.shrink();
    final fraction = (taken / expected).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$taken of $expected taken this week',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 4,
            color: Theme.of(context).colorScheme.primary,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}

/// One calendar day's doses. Mark-taken is a callback only — this widget
/// never writes a log itself, so a past or future day cannot be answered
/// from the list by accident.
class DayDoseList extends StatelessWidget {
  const DayDoseList({
    super.key,
    required this.day,
    required this.now,
    required this.occurrences,
    this.onMarkTaken,
    this.onOpenHistory,
    this.shrinkWrap = false,
    this.physics,
    this.showHeading = true,
  });

  final DateTime day;
  final DateTime now;
  final List<DayOccurrence> occurrences;
  final Future<void> Function(DayOccurrence occurrence)? onMarkTaken;
  final void Function(DayOccurrence occurrence)? onOpenHistory;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  final bool showHeading;

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: shrinkWrap,
      physics: physics,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      children: [
        _DayDoseColumn(
          day: day,
          now: now,
          occurrences: occurrences,
          onMarkTaken: onMarkTaken,
          onOpenHistory: onOpenHistory,
          showHeading: showHeading,
        ),
      ],
    );
  }
}

/// Same cards as [DayDoseList], as slivers so they share a [CustomScrollView]
/// with a collapsing calendar instead of scrolling in a leftover box.
List<Widget> dayDoseSlivers({
  required DateTime day,
  required DateTime now,
  required List<DayOccurrence> occurrences,
  Future<void> Function(DayOccurrence occurrence)? onMarkTaken,
  void Function(DayOccurrence occurrence)? onOpenHistory,
  bool showHeading = true,
}) {
  return [
    SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      sliver: SliverToBoxAdapter(
        child: _DayDoseColumn(
          day: day,
          now: now,
          occurrences: occurrences,
          onMarkTaken: onMarkTaken,
          onOpenHistory: onOpenHistory,
          showHeading: showHeading,
        ),
      ),
    ),
  ];
}

class _DayDoseColumn extends StatelessWidget {
  const _DayDoseColumn({
    required this.day,
    required this.now,
    required this.occurrences,
    this.onMarkTaken,
    this.onOpenHistory,
    this.showHeading = true,
  });

  final DateTime day;
  final DateTime now;
  final List<DayOccurrence> occurrences;
  final Future<void> Function(DayOccurrence occurrence)? onMarkTaken;
  final void Function(DayOccurrence occurrence)? onOpenHistory;
  final bool showHeading;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeading) ...[
          Text(
            _dayHeading(day, now),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
        ],
        if (occurrences.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Text(
              isSameCalendarDay(day, now)
                  ? 'Nothing due today.'
                  : 'Nothing scheduled',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          )
        else
          for (var i = 0; i < occurrences.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _DayDoseRow(
              occurrence: occurrences[i],
              day: day,
              now: now,
              onMarkTaken: onMarkTaken,
              onOpenHistory: onOpenHistory,
            ),
          ],
      ],
    );
  }
}

class _DayDoseRow extends StatefulWidget {
  const _DayDoseRow({
    required this.occurrence,
    required this.day,
    required this.now,
    this.onMarkTaken,
    this.onOpenHistory,
  });

  final DayOccurrence occurrence;
  final DateTime day;
  final DateTime now;
  final Future<void> Function(DayOccurrence occurrence)? onMarkTaken;
  final void Function(DayOccurrence occurrence)? onOpenHistory;

  @override
  State<_DayDoseRow> createState() => _DayDoseRowState();
}

class _DayDoseRowState extends State<_DayDoseRow> {
  bool _busy = false;

  bool get _canMarkTaken {
    if (widget.onMarkTaken == null) return false;
    if (!isSameCalendarDay(widget.day, widget.now)) return false;
    switch (widget.occurrence.status) {
      case DayDoseStatus.pending:
      case DayDoseStatus.upcoming:
      case DayDoseStatus.snoozed:
        return true;
      case DayDoseStatus.taken:
      case DayDoseStatus.missed:
      case DayDoseStatus.notRecorded:
        return false;
    }
  }

  bool get _canOpenHistory {
    if (widget.onOpenHistory == null) return false;
    switch (widget.occurrence.status) {
      case DayDoseStatus.taken:
      case DayDoseStatus.missed:
      case DayDoseStatus.snoozed:
      case DayDoseStatus.notRecorded:
        return true;
      case DayDoseStatus.pending:
      case DayDoseStatus.upcoming:
        return false;
    }
  }

  Future<void> _markTaken() async {
    final callback = widget.onMarkTaken;
    if (callback == null || _busy) return;
    setState(() => _busy = true);
    try {
      await callback(widget.occurrence);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final occurrence = widget.occurrence;
    final status = occurrence.status;
    final color = DayDoseStyle.color(context, status);
    final medicine = occurrence.item.medicine;
    final title = medicineTitle(medicine);
    final subtitle = _occurrenceSubtitle(occurrence);

    return Card(
      child: InkWell(
        onTap: _canOpenHistory ? () => widget.onOpenHistory!(occurrence) : null,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(DayDoseStyle.icon(status), color: color, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DayDoseStyle.label(status),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_canMarkTaken)
                      TextButton(
                        onPressed: _busy ? null : _markTaken,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(120, 48),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          alignment: Alignment.centerLeft,
                          tapTargetSize: MaterialTapTargetSize.padded,
                        ),
                        child: const Text('Mark taken'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _dayHeading(DateTime day, DateTime now) {
  final d = calendarDay(day);
  final t = calendarDay(now);
  final delta = d.difference(t).inDays;
  final date = '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
  if (delta == 0) return 'Today, $date';
  if (delta == -1) return 'Yesterday, $date';
  if (delta == 1) return 'Tomorrow, $date';
  if (d.year != t.year) return '$date ${d.year}';
  return date;
}

String _occurrenceSubtitle(DayOccurrence occurrence) {
  final local = occurrence.scheduledAt.toLocal();
  final time =
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  final dose = occurrence.item.medicine.doseAmount;
  if (dose.isEmpty) return time;
  return '$time · $dose';
}
