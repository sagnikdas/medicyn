import 'package:flutter/material.dart';

import '../../core/locale_dates.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../core/widgets/chart_grid.dart';
import '../../core/widgets/medicyn_motion.dart';
import 'day_dose_style.dart';
import 'day_occurrences.dart';
import 'reminder_copy.dart';

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
          child: MedicynAnimatedValue(
            value: fraction,
            duration: MedicynMotion.medium,
            builder: (context, value) => LinearProgressIndicator(
              value: value,
              minHeight: 4,
              color: Theme.of(context).colorScheme.primary,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest,
            ),
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
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
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
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      sliver: SliverToBoxAdapter(
        child: MedicynFadeIn(
          key: ValueKey(calendarDay(day)),
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
          ChartHandLetteredText(
            _dayHeading(day, now),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
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
        Text(label, style: Theme.of(context).textTheme.titleMedium),
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
    MedicynMotion.confirm(context);
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
    final highlight =
        status == DayDoseStatus.pending ||
        status == DayDoseStatus.upcoming ||
        status == DayDoseStatus.snoozed;
    final statusColor = DayDoseStyle.color(context, status);

    return MedicynPressable(
      enabled: _canOpenHistory || _canMarkTaken,
      child: AnimatedOpacity(
        duration: MedicynMotion.duration(context, MedicynMotion.medium),
        curve: MedicynMotion.decelerate,
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
                boxShadow: MedicynTheme.ambientShadow,
                // A soft full outline while the row still needs a response.
                // Deliberately a uniform Border.all: a BoxDecoration border
                // with per-side widths (e.g. a thicker left edge) combined
                // with borderRadius hits Flutter's non-uniform-border paint
                // path and silently drops the rest of the card's content —
                // see the leading colored tab below for how that accent is
                // done safely instead.
                border: highlight
                    ? Border.all(
                        color: statusColor.withValues(alpha: 0.25),
                        width: 1.5,
                      )
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    // The content determines the card's height. The accent
                    // is positioned after that height is known, rather than
                    // using a stretched Row child while the sliver is still
                    // being laid out with an unbounded height.
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: 4,
                      child: ColoredBox(color: statusColor),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
                      child: Row(
                        children: [
                          _StatusAvatar(status: status),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AnimatedDefaultTextStyle(
                                  duration: MedicynMotion.duration(
                                    context,
                                    MedicynMotion.fast,
                                  ),
                                  curve: MedicynMotion.decelerate,
                                  style:
                                      Theme.of(
                                        context,
                                      ).textTheme.titleMedium?.copyWith(
                                        decoration: taken
                                            ? TextDecoration.lineThrough
                                            : TextDecoration.none,
                                        color: taken
                                            ? scheme.onSurfaceVariant
                                            : scheme.onSurface,
                                      ) ??
                                      const TextStyle(),
                                  child: Text(
                                    title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
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
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
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
                                          color: DayDoseStyle.color(
                                            context,
                                            status,
                                          ),
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          MedicynSwitcher(
                            child: taken
                                ? Container(
                                    key: const ValueKey('done'),
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
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(color: scheme.secondary),
                                    ),
                                  )
                                : _canMarkTaken
                                ? IconButton(
                                    key: const ValueKey('mark'),
                                    tooltip: 'Mark taken',
                                    onPressed: _busy ? null : _markTaken,
                                    icon: Icon(
                                      Icons.check,
                                      color: highlight
                                          ? scheme.primary
                                          : scheme.outline,
                                    ),
                                    style: IconButton.styleFrom(
                                      side: BorderSide(
                                        color: highlight
                                            ? scheme.primary
                                            : scheme.outlineVariant,
                                        width: 2,
                                      ),
                                      minimumSize: const Size(48, 48),
                                    ),
                                  )
                                : const SizedBox(
                                    key: ValueKey('none'),
                                    width: 0,
                                    height: 48,
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The chart's per-row status mark: a ring in the status color holding its
/// glyph (see [DayDoseStyle.glyph]) — a miniature of the same color+mark
/// pairing used everywhere else a status appears.
///
/// Implicitly animated (`AnimatedContainer`, same element identity across a
/// status change) rather than keyed to the status and rebuilt from scratch:
/// a `KeyedSubtree(key: ValueKey(status))` here — tearing the element down
/// and remounting a new one every time a dose transitions status — hit a
/// live Flutter framework assertion ('really is our descendant') on real
/// hardware once several rows were cycling status around the same time.
/// Keeping one long-lived element and animating its properties avoids that
/// whole class of element-lifecycle risk.
class _StatusAvatar extends StatefulWidget {
  const _StatusAvatar({required this.status});
  final DayDoseStatus status;

  @override
  State<_StatusAvatar> createState() => _StatusAvatarState();
}

/// A [StatefulWidget] with a persistent controller, not an
/// `AnimatedSwitcher` keyed on status: the glyph [Icon] stays the same
/// long-lived element across a status change (see the class doc above)
/// while [_pop] drives its scale from underneath, so DESIGN.md's promised
/// "popping in with a slight overshoot" plays without ever remounting it.
class _StatusAvatarState extends State<_StatusAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    // Built here, not as `late final` field initializers: a lazy
    // initializer never touched by build() would only fire inside
    // dispose(), constructing a controller against an already-deactivated
    // element (see _AgendaAvatarState in android_today_screen.dart, which
    // hit exactly that with its own no-status early return).
    _pop = AnimationController(
      vsync: this,
      duration: MedicynMotion.medium,
      value: 1,
    );
    _scale = CurvedAnimation(parent: _pop, curve: Curves.easeOutBack);
  }

  @override
  void didUpdateWidget(covariant _StatusAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) {
      if (MedicynMotion.reduce(context)) {
        _pop.value = 1;
      } else {
        _pop.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final color = DayDoseStyle.color(context, status);
    final scheme = Theme.of(context).colorScheme;
    final due =
        status == DayDoseStatus.pending || status == DayDoseStatus.upcoming;
    final filled = status == DayDoseStatus.taken;
    return AnimatedContainer(
      duration: MedicynMotion.duration(context, MedicynMotion.fast),
      curve: MedicynMotion.decelerate,
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled
            ? color
            : due
            ? color.withValues(alpha: 0.12)
            : scheme.surfaceContainerHigh,
        border: filled
            ? null
            : Border.all(color: color.withValues(alpha: 0.6), width: 2),
      ),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: Icon(
          DayDoseStyle.glyph(status),
          size: 22,
          color: filled ? scheme.onPrimary : color,
        ),
      ),
    );
  }
}

String _dayHeading(DateTime day, DateTime now) {
  final d = calendarDay(day);
  final t = calendarDay(now);
  final delta = d.difference(t).inDays;
  final date = '${localeWeekdayAbbr(d)} ${localeDayMonth(d)}';
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
