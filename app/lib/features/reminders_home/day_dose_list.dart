import 'package:flutter/material.dart';

import '../../core/theme.dart';
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
    final grouped = groupByDayPart(occurrences);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeading) ...[
          Text(
            _dayHeading(day, now),
            style: Theme.of(context).textTheme.headlineMedium,
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
          for (final part in DayPart.values)
            if (grouped[part]!.isNotEmpty) ...[
              _DayPartHeader(part: part),
              const SizedBox(height: 12),
              for (var i = 0; i < grouped[part]!.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                _DayDoseRow(
                  occurrence: grouped[part]![i],
                  day: day,
                  now: now,
                  onMarkTaken: onMarkTaken,
                  onOpenHistory: onOpenHistory,
                ),
              ],
              const SizedBox(height: 24),
            ],
      ],
    );
  }
}

class _DayPartHeader extends StatelessWidget {
  const _DayPartHeader({required this.part});
  final DayPart part;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (part) {
      DayPart.morning => (Icons.light_mode_outlined, 'Morning'),
      DayPart.afternoon => (Icons.wb_sunny_outlined, 'Afternoon'),
      DayPart.evening => (Icons.bedtime_outlined, 'Evening'),
    };
    return Row(
      children: [
        Icon(
          icon,
          size: 22,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Text(label, style: Theme.of(context).textTheme.headlineMedium),
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
    final scheme = Theme.of(context).colorScheme;
    final medicine = occurrence.item.medicine;
    final title = medicineTitle(medicine);
    final subtitle = _occurrenceSubtitle(occurrence);
    final taken = status == DayDoseStatus.taken;
    final notes = medicine.notes.trim();
    final highlight = status == DayDoseStatus.pending ||
        status == DayDoseStatus.upcoming ||
        status == DayDoseStatus.snoozed;

    return Opacity(
      opacity: taken ? 0.75 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _canOpenHistory
              ? () => widget.onOpenHistory!(occurrence)
              : null,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
              boxShadow: DoselyTheme.ambientShadow,
              border: highlight
                  ? Border.all(color: scheme.primary.withValues(alpha: 0.2))
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  _StatusAvatar(status: status),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                decoration: taken
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: taken
                                    ? scheme.onSurfaceVariant
                                    : scheme.onSurface,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        if (notes.isNotEmpty && highlight) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              notes,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: scheme.onSecondaryContainer,
                                  ),
                            ),
                          ),
                        ],
                        if (status == DayDoseStatus.missed ||
                            status == DayDoseStatus.snoozed ||
                            status == DayDoseStatus.notRecorded) ...[
                          const SizedBox(height: 4),
                          Text(
                            DayDoseStyle.label(status),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: DayDoseStyle.color(context, status),
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (taken)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Done',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: scheme.secondary,
                        ),
                      ),
                    )
                  else if (_canMarkTaken)
                    IconButton(
                      tooltip: 'Mark taken',
                      onPressed: _busy ? null : _markTaken,
                      icon: Icon(
                        Icons.check,
                        color: highlight ? scheme.primary : scheme.outline,
                      ),
                      style: IconButton.styleFrom(
                        side: BorderSide(
                          color: highlight ? scheme.primary : scheme.outlineVariant,
                          width: 2,
                        ),
                        minimumSize: const Size(48, 48),
                      ),
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

class _StatusAvatar extends StatelessWidget {
  const _StatusAvatar({required this.status});
  final DayDoseStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final taken = status == DayDoseStatus.taken;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: taken
            ? scheme.secondaryContainer
            : status == DayDoseStatus.pending ||
                  status == DayDoseStatus.upcoming
            ? scheme.primary.withValues(alpha: 0.1)
            : scheme.surfaceContainerHigh,
      ),
      child: Icon(
        taken ? Icons.check : Icons.medication,
        color: taken ||
                status == DayDoseStatus.pending ||
                status == DayDoseStatus.upcoming
            ? scheme.primary
            : scheme.onSurfaceVariant,
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
