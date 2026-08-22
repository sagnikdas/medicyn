import 'package:flutter/material.dart';

import '../../core/widgets/dosely_layout.dart';
import '../../core/widgets/dosely_motion.dart';
import '../../data/local/database.dart';
import '../auth/auth_service.dart';
import '../reminders_home/reminder_copy.dart';
import '../reminders_home/refill.dart';
import '../review_edit/review_edit_screen.dart';
import 'care_remote_refresh.dart';
import 'care_service.dart';
import 'edit_attribution.dart';

/// The patient's reminders, read from Supabase. Used by the caregiver —
/// never writes into this phone's Drift file, because that file is what
/// arms *this* phone's alarms.
class PatientRemindersScreen extends StatefulWidget {
  const PatientRemindersScreen({
    super.key,
    required this.patientId,
    required this.patientName,
    required this.db,
  });

  final String patientId;
  final String? patientName;
  final AppDatabase db;

  @override
  State<PatientRemindersScreen> createState() => _PatientRemindersScreenState();
}

class _PatientRemindersScreenState extends State<PatientRemindersScreen> {
  List<ScheduleWithMedicine>? _items;
  Map<String, String> _names = {};
  String? _error;

  String? get _me => AuthService.instance.currentUser?.id;

  @override
  void initState() {
    super.initState();
    CareRemoteRefresh.instance.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    CareRemoteRefresh.instance.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final items = await CareService.instance.patientReminders(
        widget.patientId,
      );
      final ids = <String>{
        for (final item in items) ...[
          if (item.medicine.updatedBy != null) item.medicine.updatedBy!,
          if (item.schedule.updatedBy != null) item.schedule.updatedBy!,
        ],
      };
      final names = <String, String>{};
      final theirs = widget.patientName?.trim();
      if (theirs != null && theirs.isNotEmpty) {
        names[widget.patientId] = theirs;
      }
      for (final id in ids) {
        if (id == _me || names.containsKey(id)) continue;
        final name = await CareService.instance.displayName(id);
        if (name != null) names[id] = name;
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _names = names;
        _error = null;
      });
    } on CareLinkFailure catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  Future<void> _open({ScheduleWithMedicine? existing}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ReviewEditScreen(
          existing: existing,
          db: widget.db,
          forPatientId: widget.patientId,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final who = widget.patientName;
    return Scaffold(
      appBar: AppBar(
        title: Text(who == null ? 'Their reminders' : "$who's reminders"),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(),
        icon: const Icon(Icons.add),
        label: const Text('Add reminder'),
      ),
      body: SafeArea(
        child: DoselyContent(
          child: RefreshIndicator(onRefresh: _load, child: _body()),
        ),
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(28),
        children: [Text(_error!, textAlign: TextAlign.center)],
      );
    }
    final items = _items;
    if (items == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (items.isEmpty) {
      return DoselyFadeIn(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(28, 48, 28, 96),
          children: const [
            Text(
              'No reminders yet. Add one by filling in the form — scan and '
              'voice stay on their phone, because those send a label to a '
              'service under their consent, not yours.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return DoselyFadeIn(
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final item = items[i];
          final medicine = item.medicine;
          final attribution = editAttributionLine(
            updatedBy: item.schedule.updatedBy ?? medicine.updatedBy,
            updatedAt: item.schedule.updatedAt.isAfter(medicine.updatedAt)
                ? item.schedule.updatedAt
                : medicine.updatedAt,
            createdAt: medicine.createdAt,
            currentUserId: _me,
            nameOf: (id) => _names[id],
          );
          return Card(
            child: InkWell(
              onTap: () => _open(existing: item),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      medicineTitle(medicine),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (medicine.doseAmount.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        medicine.doseAmount,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      describeSchedule(item.schedule),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (refillWarningLine(
                          refillDaysLeft(
                            tabletsRemaining: medicine.tabletsRemaining,
                            tabletsPerDose: medicine.tabletsPerDose,
                            schedules: [item.schedule],
                          ),
                        )
                        case final warning?) ...[
                      const SizedBox(height: 4),
                      Text(
                        warning,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    if (attribution != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        attribution,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
