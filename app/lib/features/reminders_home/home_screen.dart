import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_settings.dart';
import '../../core/motion.dart';
import '../../core/widgets/dosely_chrome.dart';
import '../../core/widgets/dosely_motion.dart';
import '../../data/local/database.dart';
import '../../data/remote/care_notifier.dart';
import '../../data/remote/sync_service.dart';
import '../auth/auth_service.dart';
import '../capture_ocr/ocr_capture_screen.dart';
import '../care/care_service.dart';
import '../consent/consent_purpose.dart';
import '../consent/consent_service.dart';
import '../history/dose_history_screen.dart';
import '../notification_engine/missed_doses.dart';
import '../notification_engine/notification_actions.dart';
import '../notification_engine/notification_service.dart';
import '../push/push_service.dart';
import '../review_edit/review_edit_screen.dart';
import '../voice_capture/voice_capture_screen.dart';
import 'calendar_collapse_sliver.dart';
import 'day_dose_list.dart';
import 'day_occurrences.dart';
import 'dose_calendar.dart';
import 'refill.dart';

enum _ReminderDisposition { stop, deleteHistory }

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.db,
    this.onAvatarTap,
    this.onNames,
  });
  final AppDatabase db;

  /// Opens the Profile tab when this screen is hosted in [AppShell].
  final VoidCallback? onAvatarTap;

  /// Lets the Plan tab show the same edit-attribution names Home loaded.
  final ValueChanged<Map<String, String>>? onNames;

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Map<String, String> _names = {};
  DateTime _selectedDay = calendarDay(DateTime.now());
  Timer? _clock;
  final _scroll = ScrollController();
  bool _calendarMonth = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap(requestPermissions: true);
    // Upcoming → pending has to flip when the clock time passes, not only
    // when the user comes back from another screen.
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _scroll.dispose();
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
    if (signedIn) {
      unawaited(_reportHealth());
      unawaited(_refreshNames());
    }
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
    final items = await widget.db.activeSchedulesOnce();
    if (anyRefillLow(items)) {
      unawaited(CareNotifier.instance.refillLow());
    }
  }

  Future<void> _reportHealth() async {
    final health = await NotificationService.instance.readDeviceHealth();
    if (health == null) return;
    await CareService.instance.reportOwnDeviceHealth(health);
  }

  Future<void> _refreshNames() async {
    final me = AuthService.instance.currentUser;
    if (me == null) return;
    try {
      final link = await CareService.instance.currentLink();
      if (link == null || link.status != CareLinkStatus.active) return;
      final other = link.otherPartyId(me.id);
      if (other == null) return;
      final name = await CareService.instance.displayName(other);
      if (!mounted || name == null) return;
      setState(() => _names = {other: name});
      widget.onNames?.call(_names);
    } catch (_) {
      // Attribution falls back to "someone".
    }
  }

  Future<void> startCapture() => _startCapture();

  Future<void> edit(ScheduleWithMedicine item) => _edit(item);

  Future<void> delete(ScheduleWithMedicine item) => _delete(item);

  Future<void> _startCapture() async {
    final ocrText = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const OcrCaptureScreen()));
    if (ocrText == null || !mounted) return;

    var transcript = '';
    if (ConsentService.instance.isGranted(ConsentPurpose.googleSpeech)) {
      final spoken = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const VoiceCaptureScreen()),
      );
      if (spoken == null || !mounted) return;
      transcript = spoken;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReviewEditScreen(
          ocrText: ocrText,
          transcript: transcript,
          db: widget.db,
        ),
      ),
    );
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
            onPressed: () =>
                Navigator.pop(dialogContext, _ReminderDisposition.stop),
            child: const Text('Stop reminding me'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(
              dialogContext,
              _ReminderDisposition.deleteHistory,
            ),
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
      sync.tryDeleteRemoteMedicine(item.medicine.id).whenComplete(sync.syncAll),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: DoselyTopBar(
        onAvatarTap: widget.onAvatarTap,
        avatarLabel: AuthService.instance.currentUser?.email,
      ),
      body: StreamBuilder<List<ScheduleWithMedicine>>(
        stream: widget.db.watchSchedulesWithMedicines(),
        builder: (context, scheduleSnap) {
          return StreamBuilder<List<DoseLog>>(
            stream: widget.db.watchDoseLogs(),
            builder: (context, logSnap) {
              return _calendarBody(
                schedules: scheduleSnap.data ?? const [],
                logs: logSnap.data ?? const [],
              );
            },
          );
        },
      ),
    );
  }

  Widget _calendarBody({
    required List<ScheduleWithMedicine> schedules,
    required List<DoseLog> logs,
  }) {
    final now = DateTime.now();
    final records = <DoseRecord>[
      for (final log in logs) ?DoseRecord.tryFromLog(log),
    ];
    final rangeStart = DateTime(now.year, now.month - 18, 1);
    final rangeEnd = DateTime(now.year, now.month + 6, 1);
    final cellMarks = cellMarksForRange(
      items: schedules,
      logs: records,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      now: now,
    );
    final calendarMarks = {
      for (final e in cellMarks.entries)
        e.key: CalendarDayMarks(
          taken: e.value.hasTaken,
          pending: e.value.hasPending || e.value.hasUpcoming,
          missed: e.value.hasMissed,
          snoozed: e.value.hasSnoozed,
          notRecorded: e.value.hasNotRecorded,
        ),
    };
    final occurrences = occurrencesOnDay(
      items: schedules,
      logs: records,
      day: _selectedDay,
      now: now,
    );
    final next = isSameCalendarDay(_selectedDay, now)
        ? nextActionableDose(occurrences)
        : null;
    final takenCount = occurrences
        .where((o) => o.status == DayDoseStatus.taken)
        .length;
    final expectedCount = occurrences.length;
    final month = _calendarMonth;

    return CustomScrollView(
      controller: _scroll,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: DoselyFadeIn(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    greetingFor(now),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isSameCalendarDay(_selectedDay, now)
                        ? 'Your health schedule for today.'
                        : 'Your health schedule for this day.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        HomeCalendarSliver(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: DoseCalendar(
              selectedDay: _selectedDay,
              now: now,
              marks: calendarMarks,
              monthExpanded: month,
              onMonthExpandedChanged: _onMonthExpandedChanged,
              onSelectDay: (day) => setState(() => _selectedDay = day),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: AnimatedSize(
            duration: DoselyMotion.duration(context, DoselyMotion.medium),
            curve: DoselyMotion.decelerate,
            alignment: Alignment.topCenter,
            child: next == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: DoselyFadeIn(
                      child: _NextDoseCard(
                        occurrence: next,
                        onMarkTaken: () => _markTaken(next),
                      ),
                    ),
                  ),
          ),
        ),
        if (expectedCount > 0)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: DoselyFadeIn(
                delay: const Duration(milliseconds: 40),
                child: DailyProgressCard(
                  taken: takenCount,
                  expected: expectedCount,
                ),
              ),
            ),
          ),
        if (schedules.isEmpty)
          SliverToBoxAdapter(
            child: DoselyFadeIn(child: _EmptyState(onAdd: _startCapture)),
          )
        else
          ...dayDoseSlivers(
            day: _selectedDay,
            now: now,
            occurrences: occurrences,
            onMarkTaken: _markTaken,
            onOpenHistory: _openHistory,
          ),
      ],
    );
  }

  void _onMonthExpandedChanged(bool expanded) {
    setState(() => _calendarMonth = expanded);
    if (!expanded || !_scroll.hasClients) return;
    unawaited(
      _scroll.animateTo(
        0,
        duration: DoselyMotion.duration(context, DoselyMotion.medium),
        curve: DoselyMotion.standard,
      ),
    );
  }

  Future<void> _markTaken(DayOccurrence occurrence) async {
    DoselyMotion.confirm(context);
    await recordDoseTaken(
      widget.db,
      scheduleId: occurrence.item.schedule.id,
      scheduledAt: occurrence.scheduledAt,
      source: 'calendar',
    );
    if (AuthService.instance.currentUser == null) return;
    unawaited(SyncService(widget.db).syncAll());
  }

  void _openHistory(DayOccurrence occurrence) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DoseHistoryScreen(
          scheduleId: occurrence.item.schedule.id,
          db: widget.db,
        ),
      ),
    );
  }
}

class _NextDoseCard extends StatefulWidget {
  const _NextDoseCard({required this.occurrence, required this.onMarkTaken});

  final DayOccurrence occurrence;
  final Future<void> Function() onMarkTaken;

  @override
  State<_NextDoseCard> createState() => _NextDoseCardState();
}

class _NextDoseCardState extends State<_NextDoseCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final medicine = widget.occurrence.item.medicine;
    final local = widget.occurrence.scheduledAt.toLocal();
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    final subtitle = [
      if (medicine.strength.isNotEmpty) medicine.strength,
      if (medicine.notes.isNotEmpty) medicine.notes,
    ].join(' • ');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x3300685F),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'NEXT DOSE',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onPrimaryContainer,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                time,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(color: scheme.onPrimary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            medicine.drugName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(color: scheme.onPrimary),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.inversePrimary),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    try {
                      await widget.onMarkTaken();
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
            style: FilledButton.styleFrom(
              backgroundColor: scheme.onPrimary,
              foregroundColor: scheme.primary,
            ),
            child: const Text('Mark as Taken'),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.primaryContainer.withValues(alpha: 0.12),
            ),
            child: Icon(Icons.medication, size: 72, color: scheme.primary),
          ),
          const SizedBox(height: 24),
          Text(
            'No reminders yet',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Scan a label or speak the details to add your first one.',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text(
              'Add medicine',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Home "Daily progress" row: copy on the left, ring on the right.
@visibleForTesting
class DailyProgressCard extends StatelessWidget {
  const DailyProgressCard({
    super.key,
    required this.taken,
    required this.expected,
  });

  final int taken;
  final int expected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fraction = expected == 0 ? 0.0 : taken / expected;
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Daily progress',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          '$taken of $expected doses completed',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
    return AmbientCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: copy),
          const SizedBox(width: 12),
          ProgressRing(fraction: fraction),
        ],
      ),
    );
  }
}
