import 'package:flutter/material.dart';

import '../../core/widgets/dosely_layout.dart';
import '../../core/widgets/dosely_motion.dart';
import '../../data/local/database.dart';
import '../auth/auth_service.dart';
import '../care/edit_attribution.dart';
import 'reminder_card.dart';

/// The cabinet: every reminder, plus the place to add another. Home is the
/// calendar of a day; this screen is what you are taking.
class MedicinesListScreen extends StatelessWidget {
  const MedicinesListScreen({
    super.key,
    required this.db,
    required this.names,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    this.embedded = false,
  });

  final AppDatabase db;
  final Map<String, String> names;
  final VoidCallback onAdd;
  final Future<void> Function(ScheduleWithMedicine) onEdit;
  final Future<void> Function(ScheduleWithMedicine) onDelete;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: embedded ? null : AppBar(title: const Text('My medicines')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: onAdd,
        icon: const Icon(Icons.add),
        label: const Text('Add medicine'),
      ),
      body: DoselyContent(
        child: StreamBuilder<List<ScheduleWithMedicine>>(
          // Lifecycle states are intentionally shown here too: a paused or
          // completed course must remain reachable so the user can review
          // history or resume it without recreating the reminder.
          stream: db.watchSchedulesWithMedicines(),
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
                child: _EmptyState(onAdd: onAdd, embedded: embedded),
              );
            }
            return DoselyFadeIn(
              child: ListView.separated(
                padding: EdgeInsets.fromLTRB(20, embedded ? 24 : 16, 20, 96),
                itemCount: items.length + (embedded ? 1 : 0),
                separatorBuilder: (context, i) {
                  if (embedded && i == 0) return const SizedBox(height: 16);
                  return const SizedBox(height: 12);
                },
                itemBuilder: (context, i) {
                  if (embedded && i == 0) {
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
                  final item = items[embedded ? i - 1 : i];
                  return ReminderCard(
                    item: item,
                    db: db,
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
                      nameOf: (id) => names[id],
                    ),
                    onTap: () => onEdit(item),
                    onDelete: () => onDelete(item),
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
  const _EmptyState({required this.onAdd, this.embedded = false});
  final VoidCallback onAdd;
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
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add medicine'),
            ),
          ],
        ),
      ),
    );
  }
}
