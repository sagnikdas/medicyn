import 'package:flutter/material.dart';

import '../../data/local/database.dart';
import '../notification_engine/notification_actions.dart';

/// Full-screen "did you take this?" prompt shown when the user taps a dose
/// reminder notification's body (as opposed to its Taken/Snooze action
/// buttons, which record their action directly without opening this).
///
/// Owns a short-lived [db] connection of its own rather than the app's
/// shared singleton, matching the notification engine's existing pattern —
/// this can be reached from a cold start, before any other part of the app
/// has stood up its usual database instance.
class DoseConfirmScreen extends StatefulWidget {
  const DoseConfirmScreen({
    super.key,
    required this.scheduleId,
    required this.scheduledAt,
    required this.db,
  });

  final String scheduleId;
  final DateTime scheduledAt;
  final AppDatabase db;

  @override
  State<DoseConfirmScreen> createState() => _DoseConfirmScreenState();
}

class _DoseConfirmScreenState extends State<DoseConfirmScreen> {
  ScheduleWithMedicine? _item;
  bool _loading = true;
  bool _notFound = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    widget.db.close();
    super.dispose();
  }

  Future<void> _load() async {
    final schedule = await widget.db.scheduleById(widget.scheduleId);
    final medicine = schedule == null ? null : await widget.db.medicineById(schedule.medicineId);
    if (!mounted) return;
    if (schedule == null || medicine == null) {
      setState(() {
        _notFound = true;
        _loading = false;
      });
      return;
    }
    setState(() {
      _item = ScheduleWithMedicine(schedule, medicine);
      _loading = false;
    });
  }

  Future<void> _respond(bool taken) async {
    setState(() => _submitting = true);
    if (taken) {
      await recordDoseTaken(widget.db, scheduleId: widget.scheduleId, scheduledAt: widget.scheduledAt);
    } else {
      await recordDoseSnoozed(widget.db, scheduleId: widget.scheduleId, scheduledAt: widget.scheduledAt);
    }
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: _loading ? const CircularProgressIndicator() : (_notFound ? _notFoundView() : _body()),
        ),
      ),
    );
  }

  Widget _notFoundView() {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('This reminder no longer exists.'),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _body() {
    final medicine = _item!.medicine;
    final title = medicine.strength.isEmpty
        ? medicine.drugName
        : '${medicine.drugName} ${medicine.strength}';
    final body = medicine.doseAmount.isEmpty
        ? 'Time for your dose'
        : 'Take ${medicine.doseAmount}';
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  'NEXT DOSE',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onPrimaryContainer,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: scheme.onPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  body,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: scheme.inversePrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _submitting ? null : () => _respond(true),
            child: const Text('Mark as Taken'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _submitting ? null : () => _respond(false),
            child: const Text('Snooze 10m'),
          ),
        ],
      ),
    );
  }
}
