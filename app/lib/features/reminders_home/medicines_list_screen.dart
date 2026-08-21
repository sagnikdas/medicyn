import 'package:flutter/material.dart';

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
  });

  final AppDatabase db;
  final Map<String, String> names;
  final VoidCallback onAdd;
  final Future<void> Function(ScheduleWithMedicine) onEdit;
  final Future<void> Function(ScheduleWithMedicine) onDelete;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My medicines')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: onAdd,
        icon: const Icon(Icons.add),
        label: const Text('Add medicine'),
      ),
      body: StreamBuilder<List<ScheduleWithMedicine>>(
        stream: db.watchActiveSchedules(),
        builder: (context, snapshot) {
          final items = snapshot.data ?? [];
          if (items.isEmpty) return _EmptyState(onAdd: onAdd);
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final item = items[i];
              return ReminderCard(
                item: item,
                db: db,
                attribution: editAttributionLine(
                  updatedBy: item.schedule.updatedBy ?? item.medicine.updatedBy,
                  updatedAt: item.schedule.updatedAt.isAfter(item.medicine.updatedAt)
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
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 32, 32, 96),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.medication_outlined, size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'No reminders yet',
              style: Theme.of(context).textTheme.titleMedium,
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
