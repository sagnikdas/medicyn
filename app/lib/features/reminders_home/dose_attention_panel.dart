import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../core/app_settings.dart';
import '../../core/theme.dart';
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
        _AttentionDeck(
          occurrences: occurrences,
          now: now,
          onMarkTaken: onMarkTaken,
          onSnooze: onSnooze,
        ),
      ],
    );
  }
}

/// A bounded deck keeps a busy reminder day from turning Today into a long
/// column of identical cards. Only the front card is interactive; the next
/// two are deliberately just a visual preview of what is waiting underneath.
class _AttentionDeck extends StatefulWidget {
  const _AttentionDeck({
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
  State<_AttentionDeck> createState() => _AttentionDeckState();
}

class _AttentionDeckState extends State<_AttentionDeck> {
  late List<DayOccurrence> _remaining = List.of(widget.occurrences);
  final _handled = <String>{};

  @override
  void didUpdateWidget(covariant _AttentionDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incoming = {
      for (final occurrence in widget.occurrences)
        _attentionKey(occurrence): occurrence,
    };
    _handled.removeWhere((key) => !incoming.containsKey(key));
    final seen = <String>{};
    final next = <DayOccurrence>[];
    for (final occurrence in _remaining) {
      final key = _attentionKey(occurrence);
      final current = incoming[key];
      if (current != null && !_handled.contains(key)) {
        next.add(current);
        seen.add(key);
      }
    }
    for (final occurrence in widget.occurrences) {
      final key = _attentionKey(occurrence);
      if (!seen.contains(key) && !_handled.contains(key)) next.add(occurrence);
    }
    _remaining = next;
  }

  Future<void> _handle(DayOccurrence occurrence, {required bool snooze}) async {
    final key = _attentionKey(occurrence);
    if (!_remaining.any((item) => _attentionKey(item) == key)) return;
    final index = _remaining.indexWhere((item) => _attentionKey(item) == key);
    setState(() {
      _handled.add(key);
      _remaining.removeAt(index);
    });
    try {
      if (snooze) {
        await widget.onSnooze(occurrence);
      } else {
        await widget.onMarkTaken(occurrence);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _handled.remove(key);
        _remaining.insert(
          index.clamp(0, _remaining.length).toInt(),
          occurrence,
        );
      });
      rethrow;
    }
  }

  Future<void> _confirmAndHandle(DayOccurrence occurrence) async {
    if (!mounted) return;
    if (await _confirmTaken(occurrence) && mounted) {
      await _handle(occurrence, snooze: false);
    }
  }

  Future<bool> _confirmTaken(DayOccurrence occurrence) async {
    final medicine = medicineTitle(occurrence.item.medicine);
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              'Confirm dose',
              style: Theme.of(dialogContext).textTheme.headlineSmall,
            ),
            content: Text(
              'Have you taken $medicine? Confirm only after taking it.',
              style: Theme.of(
                dialogContext,
              ).textTheme.bodyLarge?.copyWith(height: 1.35),
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      style: TextButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        textStyle: Theme.of(
                          dialogContext,
                        ).textTheme.labelLarge?.copyWith(fontSize: 16),
                      ),
                      child: const Text('Not yet'),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        textStyle: Theme.of(
                          dialogContext,
                        ).textTheme.labelLarge?.copyWith(fontSize: 16),
                      ),
                      child: const Text('Yes, I took it'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    if (_remaining.isEmpty) return const SizedBox.shrink();
    final visible = _remaining.take(3).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = visible.length - 1; i >= 1; i--)
                Positioned(
                  top: i * 10,
                  left: i * 4,
                  right: i * 4,
                  child: ExcludeSemantics(child: _card(visible[i])),
                ),
              Dismissible(
                key: ValueKey(_attentionKey(visible.first)),
                direction: doseCanSnooze(visible.first.status)
                    ? DismissDirection.horizontal
                    : DismissDirection.startToEnd,
                confirmDismiss: (direction) async {
                  if (direction != DismissDirection.startToEnd) return true;
                  return _confirmTaken(visible.first);
                },
                background: _swipeBackground(
                  context,
                  alignment: Alignment.centerLeft,
                  icon: Icons.check_circle_outline,
                  label: 'Taken',
                ),
                secondaryBackground: _swipeBackground(
                  context,
                  alignment: Alignment.centerRight,
                  icon: Icons.snooze_outlined,
                  label: 'Snooze',
                ),
                onDismissed: (direction) {
                  unawaited(
                    _handle(
                      visible.first,
                      snooze: direction == DismissDirection.endToStart,
                    ),
                  );
                },
                child: Semantics(
                  container: true,
                  hint: _gestureHint(visible.first),
                  customSemanticsActions: {
                    CustomSemanticsAction(label: 'Mark as taken'): () =>
                        unawaited(_confirmAndHandle(visible.first)),
                    if (doseCanSnooze(visible.first.status))
                      CustomSemanticsAction(
                        label:
                            'Snooze ${AppSettings.instance.snoozeMinutes} minutes',
                      ): () =>
                          unawaited(_handle(visible.first, snooze: true)),
                  },
                  child: _card(visible.first),
                ),
              ),
            ],
          ),
        ),
        if (_remaining.length > 1)
          Text(
            '${_remaining.length} doses need attention · swipe right: taken${doseCanSnooze(_remaining.first.status) ? ' · left: snooze' : ''}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  Widget _card(DayOccurrence occurrence) {
    return _AttentionCard(occurrence: occurrence, now: widget.now);
  }
}

String _gestureHint(DayOccurrence occurrence) =>
    'Swipe right to mark taken${doseCanSnooze(occurrence.status) ? ', or left to snooze' : ''}.';

Widget _swipeBackground(
  BuildContext context, {
  required Alignment alignment,
  required IconData icon,
  required String label,
}) {
  final scheme = Theme.of(context).colorScheme;
  return Container(
    alignment: alignment,
    padding: const EdgeInsets.symmetric(horizontal: 20),
    decoration: BoxDecoration(
      color: scheme.primaryContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: scheme.onPrimaryContainer),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: scheme.onPrimaryContainer,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

String _attentionKey(DayOccurrence occurrence) =>
    '${occurrence.item.schedule.id}|${occurrence.scheduledAt.toUtc().toIso8601String()}';

class _AttentionCard extends StatelessWidget {
  const _AttentionCard({required this.occurrence, required this.now});

  final DayOccurrence occurrence;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final medicine = occurrence.item.medicine;
    final title = medicineTitle(medicine);
    final dose = medicine.doseAmount.trim();
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.28)),
        boxShadow: DoselyTheme.ambientShadow,
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 5, color: scheme.primary),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attentionWhenLabel(occurrence, now),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.primary,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.titleLarge?.copyWith(color: scheme.onSurface),
                    ),
                    if (dose.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Take $dose',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _gestureAffordance(context, scheme, occurrence),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gestureAffordance(
    BuildContext context,
    ColorScheme scheme,
    DayOccurrence occurrence,
  ) {
    final labelStyle = Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant);
    final snooze = doseCanSnooze(occurrence.status);
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: _gestureLabel(
              icon: Icons.keyboard_double_arrow_right,
              label: 'Taken',
              style: labelStyle,
              color: scheme.primary,
            ),
          ),
        ),
        if (snooze)
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: _gestureLabel(
                icon: Icons.keyboard_double_arrow_left,
                label: 'Snooze',
                style: labelStyle,
                color: scheme.primary,
              ),
            ),
          ),
      ],
    );
  }

  Widget _gestureLabel({
    required IconData icon,
    required String label,
    required TextStyle? style,
    required Color color,
  }) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 4),
      Text(label, style: style),
    ],
  );
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
