import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_settings.dart';
import '../../data/local/database.dart';
import '../../data/local/tables.dart';
import '../../data/remote/care_notifier.dart';
import '../../data/remote/sync_service.dart';
import '../auth/auth_service.dart';
import '../care/care_service.dart';
import '../care/reminder_attribution.dart';
import '../notification_engine/missed_doses.dart';
import '../notification_engine/notification_service.dart';
import '../notification_engine/schedule_validation.dart';
import '../push/push_service.dart';
import '../review_edit/capture_flow.dart';
import '../review_edit/review_edit_screen.dart';
import '../settings/settings_screen.dart';

enum _ReminderDisposition { stop, deleteHistory }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.db});
  final AppDatabase db;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  String? _otherPartyId;
  String? _otherPartyName;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap(requestPermissions: true);
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

  /// [requestPermissions] only on the first run, from `initState`. Asking on
  /// every resume meant that anyone who declined the battery-optimisation
  /// exemption got the system dialog thrown at them again every single time
  /// they returned to the app — the permission requests are one-time asks,
  /// while the re-arming below is what actually needs to happen on resume.
  ///
  /// The same flag gates the Supabase pull, for the same reason: restoring
  /// remote rows matters on a fresh install or a new device, not on every
  /// foreground. It reads all three tables in full, including every dose log
  /// ever written, which only grows.
  Future<void> _bootstrap({bool requestPermissions = false}) async {
    await NotificationService.instance.init();
    if (requestPermissions) {
      await NotificationService.instance.requestPermissions();
    }
    final signedIn = AuthService.instance.currentUser != null;
    if (signedIn && requestPermissions) {
      // Also backfills a profile for anyone who signed in before profiles
      // existed — without it their name never appears on the other side of a
      // link, and nothing would ever create the row.
      unawaited(CareService.instance.upsertOwnProfile());
      // Only needs the navigator, which exists by now. Not in `main`, where
      // PushService.init runs: a tapped alert has nowhere to open a feed
      // before runApp.
      unawaited(PushService.instance.attachForegroundListeners(db: widget.db));
    }
    // Local-only has no JWT, so Care Link RPCs and FCM registration stay
    // off until the user signs in from Settings.
    if (signedIn) {
      unawaited(PushService.instance.registerToken());
    }
    final sync = signedIn ? SyncService(widget.db) : null;
    // Pull before reconcile: a fresh install/new device has no local
    // schedules yet, so restoring them from Supabase first means reconcile
    // arms their alarms in this same pass instead of waiting for the next
    // resume.
    if (sync != null && requestPermissions) await sync.pullAll();
    await NotificationService.instance.reconcile(widget.db);
    try {
      await widget.db.pruneExpiredDoseLogs();
    } catch (_) {
      // Best-effort: a local prune failure must not skip the missed-dose
      // sweep or the push. The server job is the lasting copy.
    }
    // Before the push, so a dose recorded as missed goes up in the same pass
    // and reaches the other side without waiting for another foreground.
    await const MissedDoseDetector().sweep(widget.db);
    if (sync == null) return;
    await sync.syncAll();
    unawaited(_refreshAttribution());

    // Care alerts name dose-log ids the server reads back. Without cloud
    // backup there is no push, so there is nothing to announce.
    if (!AppSettings.instance.consentCloudBackup) return;

    // After the push, never before it: the alert names dose-log ids, and the
    // server reads those rows back to compose what the family is told. Telling
    // it about a dose that is still only on this phone would have it find
    // nothing.
    //
    // Asked of the database rather than of the sync that just ran. Using what
    // that one call happened to push made the alert depend on it succeeding end
    // to end — an upsert that commits but whose response never arrives left the
    // dose in Postgres and the alert lost for good, with nothing anywhere to
    // say so. Re-offering the window costs one request and the server drops
    // everything it has already sent.
    final missed = await widget.db.syncedMissedDoseIdsSince(
      DateTime.now().subtract(CareNotifier.announceWindow),
    );
    if (missed.isNotEmpty) {
      unawaited(CareNotifier.instance.missedDoses(missed));
    }
    if (sync.pushedEdits) {
      unawaited(CareNotifier.instance.dataChanged());
    }
  }

  Future<void> _refreshAttribution() async {
    final me = AuthService.instance.currentUser?.id;
    if (me == null) return;
    try {
      final link = await CareService.instance.currentLink();
      if (link == null || link.status != CareLinkStatus.active) {
        if (!mounted) return;
        setState(() {
          _otherPartyId = null;
          _otherPartyName = null;
        });
        return;
      }
      final other = link.otherPartyId(me);
      final name = other == null ? null : await CareService.instance.displayName(other);
      if (!mounted) return;
      setState(() {
        _otherPartyId = other;
        _otherPartyName = name;
      });
    } catch (_) {
      // A missing name only costs the attribution line, not the list.
    }
  }

  String? _attributionFor(ScheduleWithMedicine item) {
    final me = AuthService.instance.currentUser?.id;
    if (me == null) return null;
    final change = latestReminderChange(item.medicine, item.schedule);
    return reminderChangedByLine(
      ownerUserId: me,
      updatedBy: change.updatedBy,
      updatedAt: change.updatedAt,
      actorDisplayName: change.updatedBy == _otherPartyId ? _otherPartyName : null,
    );
  }

  Future<void> _startCapture() async {
    await pushCaptureThenReview(context: context, db: widget.db);
  }

  Future<void> _edit(ScheduleWithMedicine item) => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ReviewEditScreen(existing: item, db: widget.db),
        ),
      );

  Future<void> _delete(ScheduleWithMedicine item) async {
    final choice = await showDialog<_ReminderDisposition>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Stop reminding, or delete?'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Stop reminding me: reminders for this medicine will stop. '
                'Your dose history is kept. A linked family member can still '
                'see that history.',
              ),
              SizedBox(height: 16),
              Text(
                'Delete this medicine and its history: the medicine, its '
                'reminder, and its dose history are removed from this phone '
                'and from the cloud backup. A linked family member will no '
                'longer see them. This cannot be undone.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, _ReminderDisposition.stop),
            child: const Text('Stop reminding me'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () =>
                Navigator.pop(dialogContext, _ReminderDisposition.deleteHistory),
            child: const Text('Delete medicine and history'),
          ),
        ],
      ),
    );
    if (choice == null) return;

    final by = AuthService.instance.currentUser?.id;
    if (choice == _ReminderDisposition.stop) {
      await NotificationService.instance.cancelForSchedule(item.schedule);
      await widget.db.deactivateSchedule(item.schedule.id, by: by);
      _syncThenNotify();
      return;
    }

    final related = await widget.db.schedulesForMedicine(item.medicine.id);
    for (final schedule in related) {
      await NotificationService.instance.cancelForSchedule(schedule);
    }
    await widget.db.deleteMedicineAndHistory(item.medicine.id, by: by);
    if (AuthService.instance.currentUser == null) return;
    final sync = SyncService(widget.db);
    unawaited(
      sync.tryDeleteRemoteMedicine(item.medicine.id).whenComplete(() async {
        await sync.syncAll();
        if (sync.pushedEdits) await CareNotifier.instance.dataChanged();
      }),
    );
  }

  void _syncThenNotify() {
    if (AuthService.instance.currentUser == null) return;
    final sync = SyncService(widget.db);
    unawaited(() async {
      await sync.syncAll();
      if (sync.pushedEdits) await CareNotifier.instance.dataChanged();
    }());
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
              MaterialPageRoute(builder: (_) => SettingsScreen(db: widget.db)),
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
                db: widget.db,
                attribution: _attributionFor(item),
                onTap: () => _edit(item),
                onDelete: () => _delete(item),
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
  const _ReminderCard({
    required this.item,
    required this.db,
    required this.onTap,
    required this.onDelete,
    this.attribution,
  });
  final ScheduleWithMedicine item;
  final AppDatabase db;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final String? attribution;

  String _describe() {
    final s = item.schedule;
    // A row stored before these fields were validated can still be here, and
    // this runs for every card in the list — so an unrecognised frequency
    // would blank the whole screen rather than one row.
    final frequency = frequencyTypeFromName(s.frequencyType);
    if (frequency == null) return 'Schedule needs attention';
    switch (frequency) {
      case FrequencyType.daily:
        return 'Daily at ${s.times.join(', ')}';
      case FrequencyType.specificDays:
        const labels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
        // Same reason: labels[9] is a RangeError, not a missing label.
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
                    if (attribution != null) ...[
                      const SizedBox(height: 4),
                      Text(attribution!, style: Theme.of(context).textTheme.bodySmall),
                    ],
                    _SnoozeStatus(db: db, scheduleId: item.schedule.id),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Stop or delete',
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows "Snoozed until HH:mm" under a reminder while its most recent dose
/// log is an active (< 10 minutes old) snooze, then disappears on its own.
///
/// Polls rather than watches: the notification engine records Taken/Snooze
/// through its own `AppDatabase` instance — often from a background isolate
/// when the user snoozes straight from the notification tray — and those
/// writes don't push to a `.watch()` stream on a different instance. See
/// [AppDatabase.latestDoseLogOnce].
class _SnoozeStatus extends StatefulWidget {
  const _SnoozeStatus({required this.db, required this.scheduleId});
  final AppDatabase db;
  final String scheduleId;

  @override
  State<_SnoozeStatus> createState() => _SnoozeStatusState();
}

class _SnoozeStatusState extends State<_SnoozeStatus> {
  /// While a snooze is on screen the countdown has to expire promptly, so it
  /// is checked often. The rest of the time — which is almost all of the
  /// time, for almost every card — a slower beat is enough to notice a
  /// snooze made from the notification tray. The old fixed 15s ran per
  /// visible card for as long as the app was open, so a list of eight
  /// reminders meant ~32 database reads a minute to display nothing.
  static const _activePollInterval = Duration(seconds: 15);
  static const _idlePollInterval = Duration(minutes: 1);

  Timer? _poll;
  DateTime? _snoozedUntil;

  @override
  void initState() {
    super.initState();
    _tick();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _tick() async {
    await _refresh();
    if (!mounted) return;
    _poll = Timer(
      _snoozedUntil == null ? _idlePollInterval : _activePollInterval,
      _tick,
    );
  }

  Future<void> _refresh() async {
    final log = await widget.db.latestDoseLogOnce(widget.scheduleId);
    if (!mounted) return;
    DateTime? until;
    if (log != null && log.action == DoseAction.snoozed.name) {
      final candidate = log.loggedAt.add(const Duration(minutes: 10));
      if (candidate.isAfter(DateTime.now())) until = candidate;
    }
    if (until != _snoozedUntil) setState(() => _snoozedUntil = until);
  }

  @override
  Widget build(BuildContext context) {
    final until = _snoozedUntil;
    if (until == null) return const SizedBox.shrink();
    final local = until.toLocal();
    final label =
        'Snoozed until ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    final color = Theme.of(context).colorScheme.tertiary;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.snooze, size: 15, color: color),
          const SizedBox(width: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color)),
        ],
      ),
    );
  }
}
