import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/app_settings.dart';
import '../../data/local/database.dart';
import 'reminder_health.dart';
import 'notification_service.dart';

class ReminderReliabilityScreen extends StatefulWidget {
  const ReminderReliabilityScreen({super.key, required this.db});

  final AppDatabase db;

  @override
  State<ReminderReliabilityScreen> createState() =>
      _ReminderReliabilityScreenState();
}

class _ReminderReliabilityScreenState extends State<ReminderReliabilityScreen> {
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await NotificationService.instance.retryTimezoneInitialization();
      final report = await NotificationService.instance.reconcile(widget.db);
      final ownerId = AppSettings.instance.consentOwnerId;
      if (ownerId != null) {
        await ReminderHealthStore.instance.updateFromReconcile(
          ownerId: ownerId,
          report: report,
          permissions: await NotificationService.instance.readPermissionState(),
          timezoneReady: NotificationService.instance.timezoneReady,
        );
      }
    } catch (error) {
      _error = 'Could not check reminder access. Try again.';
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _requestNotifications() async {
    await NotificationService.instance.requestNotificationPermission();
    await _refresh();
  }

  Future<void> _requestExactAlarms() async {
    await NotificationService.instance.requestExactAlarmPermission();
    await _refresh();
  }

  Future<void> _openSystemSettings() async {
    await openAppSettings();
    await _refresh();
  }

  Future<void> _testReminder() async {
    await NotificationService.instance.showTestReminder();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Test reminder sent.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reminder reliability')),
      body: ListenableBuilder(
        listenable: ReminderHealthStore.instance,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Make sure Dosely can reach you when a dose is due.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  title: Text(_error!),
                  trailing: IconButton(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Retry',
                  ),
                ),
              ),
            for (final action in _actions()) action,
            const SizedBox(height: 12),
            Text(
              'Schedule status',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (ReminderHealthStore.instance.items.isEmpty)
              const Text('No active scheduled reminders need checking.')
            else
              ...ReminderHealthStore.instance.items.asMap().entries.map(
                (entry) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    entry.value.needsAttention
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline,
                    color: entry.value.needsAttention
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.primary,
                  ),
                  title: Text('Reminder ${entry.key + 1}'),
                  subtitle: Text(entry.value.shortStatus),
                ),
              ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _working ? null : _testReminder,
              icon: const Icon(Icons.notifications_active_outlined),
              label: const Text('Send a test reminder'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _working ? null : _refresh,
              child: Text(_working ? 'Checking…' : 'Check again'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions() {
    final permission = _permission;
    final actions = <Widget>[];
    if (permission != null && !permission.notificationsAllowed) {
      actions.add(
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Notifications are off'),
          subtitle: const Text(
            'Dosely cannot show a reminder until notifications are allowed.',
          ),
          trailing: TextButton(
            onPressed: _working ? null : _requestNotifications,
            child: const Text('Enable'),
          ),
        ),
      );
    }
    if (permission != null && !permission.exactAlarmsAllowed) {
      actions.add(
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Exact timing is off'),
          subtitle: const Text(
            'Reminders remain armed with Android’s inexact fallback and may be delayed.',
          ),
          trailing: TextButton(
            onPressed: _working ? null : _requestExactAlarms,
            child: const Text('Improve timing'),
          ),
        ),
      );
    }
    if (!NotificationService.instance.timezoneReady) {
      actions.add(
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Timezone needs setup'),
          subtitle: const Text(
            'Dosely will not schedule a reminder until the device timezone is available.',
          ),
          trailing: TextButton(
            onPressed: _working ? null : _refresh,
            child: const Text('Retry'),
          ),
        ),
      );
    }
    actions.add(
      TextButton(
        onPressed: _working ? null : _openSystemSettings,
        child: const Text('Open Android notification settings'),
      ),
    );
    return actions;
  }

  ReminderPermissionState? get _permission {
    // The persisted schedule rows are authoritative for the card; this screen
    // refreshes live permission state during _refresh. Keeping the last read
    // state in the store avoids another platform round-trip during build.
    final items = ReminderHealthStore.instance.items;
    if (items.isEmpty) return null;
    final first = items.first;
    return ReminderPermissionState(
      notificationsAllowed: first.notificationsAllowed,
      exactAlarmsAllowed: first.exactAlarmsAllowed,
    );
  }
}
