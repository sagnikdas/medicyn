import 'package:flutter/material.dart';

import '../../data/local/database.dart';
import '../../data/local/tables.dart';
import '../../data/remote/sync_service.dart';
import '../capture_ocr/ocr_capture_screen.dart';
import '../notification_engine/notification_service.dart';
import '../review_edit/review_edit_screen.dart';
import '../settings/settings_screen.dart';
import '../voice_capture/voice_capture_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.db});
  final AppDatabase db;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-arm every schedule's alarms and push anything unsynced whenever the
    // app comes back to the foreground — the mitigation for OEMs that
    // silently drop background alarms (see notification_service.dart).
    if (state == AppLifecycleState.resumed) _bootstrap();
  }

  Future<void> _bootstrap() async {
    await NotificationService.instance.init();
    await NotificationService.instance.requestPermissions();
    await NotificationService.instance.reconcile(widget.db);
    await SyncService(widget.db).syncAll();
  }

  Future<void> _startCapture() async {
    final ocrText = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const OcrCaptureScreen()),
    );
    if (ocrText == null || !mounted) return;

    final transcript = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const VoiceCaptureScreen()),
    );
    if (transcript == null || !mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReviewEditScreen(ocrText: ocrText, transcript: transcript, db: widget.db),
      ),
    );
  }

  Future<void> _edit(ScheduleWithMedicine item) => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ReviewEditScreen(existing: item, db: widget.db),
        ),
      );

  Future<void> _delete(Schedule schedule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this reminder?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;
    await NotificationService.instance.cancelForSchedule(schedule);
    await widget.db.deactivateSchedule(schedule.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dosely'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startCapture,
        icon: const Icon(Icons.add),
        label: const Text('Add medicine'),
      ),
      body: StreamBuilder<List<ScheduleWithMedicine>>(
        stream: widget.db.watchActiveSchedules(),
        builder: (context, snapshot) {
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return _EmptyState(onAdd: _startCapture);
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final item = items[i];
              return _ReminderCard(
                item: item,
                onTap: () => _edit(item),
                onDelete: () => _delete(item.schedule),
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
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.medication_outlined, size: 72, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'No reminders yet',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Scan a label or just speak the details — tap Add medicine to start.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({required this.item, required this.onTap, required this.onDelete});
  final ScheduleWithMedicine item;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  String _describe() {
    final s = item.schedule;
    final frequency = FrequencyType.values.byName(s.frequencyType);
    switch (frequency) {
      case FrequencyType.daily:
        return 'Daily at ${s.times.join(', ')}';
      case FrequencyType.specificDays:
        const labels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
        final days = s.daysOfWeek.map((d) => labels[d]).join(', ');
        return '$days at ${s.times.join(', ')}';
      case FrequencyType.everyXHours:
        return 'Every ${s.intervalHours ?? '?'} hours';
      case FrequencyType.asNeeded:
        return 'As needed';
    }
  }

  @override
  Widget build(BuildContext context) {
    final medicine = item.medicine;
    final title = medicine.strength.isEmpty ? medicine.drugName : '${medicine.drugName} ${medicine.strength}';
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    if (medicine.doseAmount.isNotEmpty)
                      Text(medicine.doseAmount, style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 4),
                    Text(_describe(), style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Remove reminder',
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
