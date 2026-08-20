import 'package:flutter/material.dart';

import '../../core/app_navigation.dart';
import '../../data/local/database.dart';
import '../../data/local/tables.dart';
import '../auth/auth_service.dart';
import '../notification_engine/schedule_validation.dart';
import '../review_edit/capture_flow.dart';
import '../review_edit/review_edit_screen.dart';
import 'care_service.dart';
import 'patient_reminder.dart';
import 'reminder_attribution.dart';

/// Opens [patientId]'s reminders from a tapped "a reminder was changed"
/// notification. A null navigator is a no-op, same as [openFeedForPatient].
void openPatientReminders(String patientId) {
  navigatorKey.currentState?.push(
    MaterialPageRoute(
      builder: (_) => PatientRemindersScreen(
        patientId: patientId,
        db: AppDatabase(),
      ),
    ),
  );
}

/// The caregiver's view of a patient's medicines: add and edit, never delete.
///
/// Reads and writes Postgres under the patient's `user_id`. The local
/// encrypted file on this phone belongs to the caregiver and must not hold
/// these rows.
class PatientRemindersScreen extends StatefulWidget {
  const PatientRemindersScreen({
    super.key,
    required this.patientId,
    required this.db,
    this.patientName,
  });

  final String patientId;
  final AppDatabase db;
  final String? patientName;

  @override
  State<PatientRemindersScreen> createState() => _PatientRemindersScreenState();
}

class _PatientRemindersScreenState extends State<PatientRemindersScreen> {
  List<PatientReminder>? _reminders;
  String? _error;
  String? _patientName;
  String? _myName;
  bool _loading = true;

  String get _myId => AuthService.instance.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _patientName = widget.patientName;
    _load();
  }

  Future<void> _load() async {
    try {
      final reminders = await CareService.instance.patientReminders(widget.patientId);
      final patientName = _patientName ??
          await CareService.instance.displayName(widget.patientId);
      final myName = _myId.isEmpty ? null : await CareService.instance.displayName(_myId);
      if (!mounted) return;
      setState(() {
        _reminders = reminders;
        _patientName = patientName;
        _myName = myName;
        _error = null;
        _loading = false;
      });
    } on CareLinkFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  String? _nameFor(String? userId) {
    if (userId == null) return null;
    if (userId == widget.patientId) return _patientName;
    if (userId == _myId) return _myName;
    return null;
  }

  Future<void> _add() async {
    final saved = await pushCaptureThenReview(
      context: context,
      db: widget.db,
      ownerUserId: widget.patientId,
      ownerDisplayName: _patientName,
    );
    if (saved && mounted) await _load();
  }

  Future<void> _edit(PatientReminder reminder) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ReviewEditScreen(
          existing: reminder.asScheduleWithMedicine,
          db: widget.db,
          ownerUserId: widget.patientId,
          ownerDisplayName: _patientName,
        ),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final who = _patientName ?? 'them';
    return Scaffold(
      appBar: AppBar(title: Text("$who's reminders")),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Add reminder'),
      ),
      body: SafeArea(child: _body(who)),
    );
  }

  Widget _body(String who) {
    if (_loading && _reminders == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _reminders == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    final items = _reminders ?? const <PatientReminder>[];
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.medication_outlined,
                size: 72,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'No reminders yet',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Add one for $who. It will ring on their phone, not yours.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final item = items[i];
          final change = latestReminderChange(item.medicine, item.schedule);
          return _RemoteReminderCard(
            reminder: item,
            attribution: reminderChangedByLine(
              ownerUserId: widget.patientId,
              updatedBy: change.updatedBy,
              updatedAt: change.updatedAt,
              actorDisplayName: _nameFor(change.updatedBy),
            ),
            onTap: () => _edit(item),
          );
        },
      ),
    );
  }
}

class _RemoteReminderCard extends StatelessWidget {
  const _RemoteReminderCard({
    required this.reminder,
    required this.onTap,
    this.attribution,
  });

  final PatientReminder reminder;
  final VoidCallback onTap;
  final String? attribution;

  String _describe() {
    final s = reminder.schedule;
    final frequency = frequencyTypeFromName(s.frequencyType);
    if (frequency == null) return 'Schedule needs attention';
    switch (frequency) {
      case FrequencyType.daily:
        return 'Daily at ${s.times.join(', ')}';
      case FrequencyType.specificDays:
        const labels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
        final days = schedulableDays(s.daysOfWeek).map((d) => labels[d]).join(', ');
        return '$days at ${s.times.join(', ')}';
      case FrequencyType.everyXHours:
        return 'Every ${s.intervalHours ?? '?'} hours';
      case FrequencyType.asNeeded:
        return 'As needed';
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(reminder.title, style: text.titleMedium),
              const SizedBox(height: 4),
              if (reminder.doseAmount.isNotEmpty)
                Text(reminder.doseAmount, style: text.bodyMedium),
              const SizedBox(height: 4),
              Text(_describe(), style: text.bodySmall),
              if (attribution != null) ...[
                const SizedBox(height: 4),
                Text(attribution!, style: text.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
