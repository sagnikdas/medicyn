import 'package:flutter/material.dart';

import '../../core/widgets/dosely_chrome.dart';
import '../../core/widgets/dosely_layout.dart';
import '../../core/widgets/dosely_motion.dart';
import '../../data/local/database.dart';
import '../auth/auth_service.dart';
import '../care/edit_attribution.dart';
import 'reminder_card.dart';

/// The cabinet: every reminder, plus the place to add another. Home is the
/// calendar of a day; this screen is what you are taking.
class MedicinesListScreen extends StatefulWidget {
  const MedicinesListScreen({
    super.key,
    required this.db,
    required this.names,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    this.embedded = false,
    this.active = true,
  });

  final AppDatabase db;
  final Map<String, String> names;
  final VoidCallback onAdd;
  final Future<void> Function(ScheduleWithMedicine) onEdit;
  final Future<void> Function(ScheduleWithMedicine) onDelete;
  final bool embedded;
  final bool active;

  @override
  State<MedicinesListScreen> createState() => _MedicinesListScreenState();
}

class _MedicinesListScreenState extends State<MedicinesListScreen> {
  late final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant MedicinesListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        _scrollController.jumpTo(0);
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.embedded
          ? AppBar(
              automaticallyImplyLeading: false,
              toolbarHeight: 64,
              titleSpacing: 20,
              title: const DoselyBrandMark(compact: true),
            )
          : AppBar(title: const Text('My medicines')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: widget.onAdd,
        icon: const Icon(Icons.add),
        label: const Text('Add medicine'),
      ),
      body: DoselyContent(
        child: StreamBuilder<List<ScheduleWithMedicine>>(
          // Lifecycle states are intentionally shown here too: a paused or
          // completed course must remain reachable so the user can review
          // history or resume it without recreating the reminder.
          stream: widget.db.watchSchedulesWithMedicines(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_outlined, size: 48),
                      const SizedBox(height: 12),
                      const Text(
                        'Could not load your reminders. Your saved data is still on this phone.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            }
            final items = snapshot.data ?? const <ScheduleWithMedicine>[];
            if (items.isEmpty) {
              return DoselyFadeIn(
                child: _EmptyState(embedded: widget.embedded),
              );
            }
            return DoselyFadeIn(
              child: ListView.separated(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
                itemCount: items.length + (widget.embedded ? 1 : 0),
                separatorBuilder: (context, i) {
                  return const SizedBox(height: 12);
                },
                itemBuilder: (context, i) {
                  if (widget.embedded && i == 0) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your plan',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Everything you take, and when.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    );
                  }
                  final item = items[widget.embedded ? i - 1 : i];
                  return ReminderCard(
                    item: item,
                    db: widget.db,
                    attribution: editAttributionLine(
                      updatedBy:
                          item.schedule.updatedBy ?? item.medicine.updatedBy,
                      updatedAt:
                          item.schedule.updatedAt.isAfter(
                            item.medicine.updatedAt,
                          )
                          ? item.schedule.updatedAt
                          : item.medicine.updatedAt,
                      createdAt: item.medicine.createdAt,
                      currentUserId: AuthService.instance.currentUser?.id,
                      nameOf: (id) => widget.names[id],
                    ),
                    onTap: () => widget.onEdit(item),
                    onDelete: () => widget.onDelete(item),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.embedded = false});
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 32, 32, 96),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (embedded) ...[
              Text(
                'Your plan',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
            ],
            Icon(
              Icons.medication_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'No reminders yet',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Scan a label or speak the details.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
