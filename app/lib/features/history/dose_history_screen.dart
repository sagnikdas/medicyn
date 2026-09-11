import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/widgets/medicyn_layout.dart';
import '../../core/widgets/medicyn_motion.dart';
import '../../data/local/database.dart';
import '../../data/local/tables.dart';
import '../../data/remote/sync_service.dart';

/// Read-only view of a single schedule's dose history — every "Taken",
/// "Snoozed", or "Missed" entry ever logged for it, newest first. Reached
/// from the edit form and from a historical row on the home calendar.
///
/// The Taken/Missed/Snoozed label is never edited. A user who disagrees
/// attaches a correction note instead.
class DoseHistoryScreen extends StatelessWidget {
  const DoseHistoryScreen({
    super.key,
    required this.scheduleId,
    required this.db,
  });

  final String scheduleId;
  final AppDatabase db;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dose history')),
      body: SafeArea(
        child: MedicynContent(
          child: FutureBuilder<Schedule?>(
            // Loaded once for the whole screen — every log here belongs to
            // this one schedule, so its frequency type doesn't vary row to
            // row the way `log.source` does.
            future: db.scheduleById(scheduleId),
            builder: (context, scheduleSnapshot) {
              final isAsNeededSchedule =
                  scheduleSnapshot.data?.frequencyType ==
                  FrequencyType.asNeeded.name;
              return StreamBuilder<List<DoseLogWithContest>>(
                stream: db.watchDoseLogsWithContests(scheduleId),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final rows = List.of(snapshot.data!)..sort(
                    (a, b) => b.log.scheduledAt.compareTo(a.log.scheduledAt),
                  );
                  if (rows.isEmpty) {
                    return MedicynFadeIn(child: _EmptyState());
                  }
                  return MedicynFadeIn(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, i) => _DoseLogCard(
                        log: rows[i].log,
                        contest: rows[i].contest,
                        db: db,
                        isAsNeededSchedule: isAsNeededSchedule,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'No history yet',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Doses you take, snooze, or miss will show up here.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _DoseLogCard extends StatelessWidget {
  const _DoseLogCard({
    required this.log,
    required this.contest,
    required this.db,
    required this.isAsNeededSchedule,
  });
  final DoseLog log;
  final DoseLogContest? contest;
  final AppDatabase db;

  /// Whether the schedule this log belongs to is an as-needed (PRN) one —
  /// see [_isPrnLog].
  final bool isAsNeededSchedule;

  DoseAction get _action => DoseAction.values.byName(log.action);

  /// A manually logged PRN dose — the "Log now" button (see
  /// `recordAsNeededDoseTaken`) — rather than a response to a scheduled
  /// reminder.
  ///
  /// `log.source == 'manual'` alone isn't a safe enough signal: today only
  /// PRN logging writes it, but nothing stops a future manual correction to
  /// a *scheduled* dose from reusing the same string. Requiring the
  /// schedule itself to be as-needed is what keeps this label from ever
  /// being pinned on an ordinary scheduled dose.
  bool get _isPrnLog => isAsNeededSchedule && log.source == 'manual';

  ({IconData icon, Color color, String label}) _actionVisuals(
    BuildContext context,
  ) {
    final scheme = Theme.of(context).colorScheme;
    switch (_action) {
      case DoseAction.taken:
        return (
          icon: Icons.check_rounded,
          color: scheme.primary,
          label: 'Taken',
        );
      case DoseAction.snoozed:
        return (
          icon: Icons.panorama_fish_eye_rounded,
          color: scheme.tertiary,
          label: 'Snoozed',
        );
      case DoseAction.missed:
        return (
          icon: Icons.change_history_rounded,
          color: scheme.error,
          label: 'Missed',
        );
    }
  }

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour < 12 ? 'AM' : 'PM';
    return '${local.month}/${local.day}/${local.year} at $hour12:$minute $period';
  }

  Future<void> _editNote(BuildContext context) async {
    final saved = await showAdaptiveDialog<String>(
      context: context,
      builder: (dialogContext) =>
          _ContestNoteDialog(initial: contest?.note ?? ''),
    );
    if (saved == null) return;
    await db.upsertDoseLogContest(doseLogId: log.id, note: saved);
    unawaited(SyncService(db).syncAll());
  }

  @override
  Widget build(BuildContext context) {
    final visuals = _actionVisuals(context);
    final hasNote = contest != null && contest!.note.isNotEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(visuals.icon, color: visuals.color, size: 40),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          visuals.label,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(
                            context,
                          ).textTheme.titleMedium?.copyWith(
                            color: visuals.color,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (_isPrnLog) ...[
                        const SizedBox(width: 8),
                        const _PrnBadge(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Scheduled for ${_formatDateTime(log.scheduledAt)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Logged ${_formatDateTime(log.loggedAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (hasNote) ...[
                    const SizedBox(height: 8),
                    Text(
                      contest!.note,
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => _editNote(context),
                    child: Text(hasNote ? 'Edit note' : "This isn't right"),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContestNoteDialog extends StatefulWidget {
  const _ContestNoteDialog({required this.initial});
  final String initial;

  @override
  State<_ContestNoteDialog> createState() => _ContestNoteDialogState();
}

class _ContestNoteDialogState extends State<_ContestNoteDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial.trim().isNotEmpty;
    return AlertDialog.adaptive(
      title: Text(editing ? 'Edit note' : 'Add a note'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 4,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'Add a note about what actually happened.',
        ),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _controller.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// A compact "As needed" tag for a PRN dose log — see
/// [_DoseLogCard._isPrnLog] — so history reads distinguishably from an
/// on-time scheduled dose at a glance, without requiring the reader to
/// compare `scheduledAt` and `loggedAt` themselves (both equal "now" for a
/// PRN log, which otherwise looks exactly like a dose answered right on
/// time).
class _PrnBadge extends StatelessWidget {
  const _PrnBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'As needed',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onSecondaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
