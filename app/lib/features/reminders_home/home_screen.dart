import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_settings.dart';
import '../../core/motion.dart';
import '../../core/widgets/dosely_chrome.dart';
import '../../core/widgets/dosely_motion.dart';
import '../../core/telemetry.dart';
import '../../data/local/database.dart';
import '../../data/local/tables.dart';
import '../../data/remote/care_notifier.dart';
import '../../data/remote/sync_service.dart';
import '../../data/remote/sync_status.dart';
import '../auth/auth_service.dart';
import '../capture_ocr/ocr_capture_screen.dart';
import '../care/care_service.dart';
import '../history/dose_history_screen.dart';
import '../notification_engine/missed_doses.dart';
import '../notification_engine/notification_actions.dart';
import '../notification_engine/reminder_health.dart';
import '../notification_engine/notification_service.dart';
import '../notification_engine/reminder_reliability_screen.dart';
import '../push/push_service.dart';
import '../review_edit/review_edit_screen.dart';
import '../voice_capture/voice_capture_screen.dart';
import 'calendar_collapse_sliver.dart';
import 'day_dose_list.dart';
import 'day_occurrences.dart';
import 'dose_attention_panel.dart';
import 'dose_calendar.dart';
import 'refill.dart';

enum _ReminderDisposition { stop, deleteHistory }

enum _CaptureMethod { scan, speak, manual }

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.db,
    this.onNames,
    this.onNeedsAttention,
    this.active = true,
  });
  final AppDatabase db;

  /// Lets the Plan tab show the same edit-attribution names Home loaded.
  final ValueChanged<Map<String, String>>? onNames;

  /// Switch to the Today tab when a dose needs answering, so opening the
  /// app from Plan or Insights still lands on Taken / Snooze.
  final VoidCallback? onNeedsAttention;

  /// The shell keeps Today mounted in an IndexedStack. Reset its calendar
  /// list when the user enters the tab so it always opens at the beginning.
  final bool active;

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Map<String, String> _names = {};
  DateTime _selectedDay = calendarDay(DateTime.now());
  Timer? _clock;

  // Opened once, deliberately, rather than in `build`. A StreamBuilder
  // re-subscribes whenever the stream instance changes, so calling
  // `db.watchX()` from build re-ran both of these queries on every rebuild
  // — including the sixty an hour the clock timer below fires, and one for
  // every calendar day tap. Over a full 24 months of retained history that
  // measured 24ms of query and subscription churn per rebuild against
  // 2.5ms for a stream opened once.
  late final Stream<List<ScheduleWithMedicine>> _schedulesStream = widget.db
      .watchSchedulesWithMedicines();
  late final Stream<List<DoseLog>> _doseLogsStream = widget.db.watchDoseLogs();
  final _scroll = ScrollController();
  bool _calendarMonth = false;
  List<DayOccurrence> _ringIfLeft = const [];
  final _dismissedAttentionUntil = <String, DateTime>{};
  final _attentionScheduleVersions = <String, DateTime>{};
  var _attentionWasPresent = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    doseResponseEvents.addListener(_onDoseResponse);
    _bootstrap(firstLoad: true);
    // Upcoming → pending has to flip when the clock time passes, not only
    // when the user comes back from another screen. Fifteen seconds is
    // short enough to notice an alarm that fired while the app is open.
    _clock = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      setState(() {});
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(_silenceIfRinging());
      }
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _scroll.dispose();
    doseResponseEvents.removeListener(_onDoseResponse);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        _scroll.jumpTo(0);
      });
    }
  }

  void _onDoseResponse() {
    final event = doseResponseEvents.value;
    if (!mounted || event == null || event.action != DoseAction.snoozed) {
      return;
    }
    final delay = Duration(minutes: AppSettings.instance.snoozeMinutes);
    setState(() {
      _dismissedAttentionUntil[_attentionKeyForValues(
        event.scheduleId,
        event.scheduledAt,
      )] = DateTime.now().add(
        delay,
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-arm every schedule's alarms and push anything unsynced whenever the
    // app comes back to the foreground — the mitigation for OEMs that
    // silently drop background alarms (see notification_service.dart).
    if (state == AppLifecycleState.resumed) _bootstrap();
    if (state == AppLifecycleState.paused) unawaited(_reRingUnanswered());
  }

  /// Permission prompts belong to reminder Save, where the user understands
  /// why Android is asking. Home only reads and surfaces the resulting state.
  ///
  /// The same flag gates the *full* Supabase pull, for the same reason:
  /// restoring dose-log history wholesale matters on a fresh install or a new
  /// device, not on every foreground, and that table only grows. Every
  /// resume still runs [SyncService.pullEditableTables] below — medicines,
  /// schedules, and contest notes are cheap, and skipping them would let the
  /// push that follows blind-overwrite an edit made elsewhere while this
  /// device was away.
  Future<void> _bootstrap({bool firstLoad = false}) async {
    await NotificationService.instance.init();
    final signedIn = AuthService.instance.currentUser != null;
    if (signedIn && firstLoad) {
      // Also backfills a profile for anyone who signed in before profiles
      // existed — without it their name never appears on the other side of a
      // link, and nothing would ever create the row.
      unawaited(CareService.instance.upsertOwnProfile());
    }
    // Local-only has no JWT, so Care Link RPCs and FCM registration stay
    // off until the user signs in from Settings.
    if (signedIn && AppSettings.instance.consentCareShare) {
      // Only needs the navigator, which exists by now. It is deliberately
      // account/consent gated rather than attached globally at startup.
      unawaited(PushService.instance.attachForegroundListeners(db: widget.db));
      unawaited(PushService.instance.registerToken());
    }
    final sync = signedIn ? SyncService(widget.db) : null;
    final syncOwner = AppSettings.instance.consentOwnerId;
    if (sync != null &&
        syncOwner != null &&
        AppSettings.instance.consentCloudBackup) {
      await SyncStatusStore.instance.markSyncing(syncOwner);
    }
    // Pull before reconcile: a fresh install/new device has no local
    // schedules yet, so restoring them from Supabase first means reconcile
    // arms their alarms in this same pass instead of waiting for the next
    // resume.
    if (sync != null) {
      if (firstLoad) {
        await sync.pullAll();
      } else {
        await sync.pullEditableTables();
      }
    }
    // Stop a looping alarm that is already on screen. Opening the app is
    // the answer; they should not have to find that row in the shade.
    // Reconcile afterwards puts the repeating series back (cancel of a
    // fired daily id also drops AlarmManager for that id).
    await NotificationService.instance.dismissActiveReminderNotifications();
    final reconcile = await NotificationService.instance.reconcile(widget.db);
    final ownerId = AppSettings.instance.consentOwnerId;
    if (ownerId != null) {
      final permissions = await NotificationService.instance
          .readPermissionState();
      await ReminderHealthStore.instance.updateFromReconcile(
        ownerId: ownerId,
        report: reconcile,
        permissions: permissions,
        timezoneReady: NotificationService.instance.timezoneReady,
      );
      await DoselyTelemetry.instance.record(
        DoselyEvent.reminderArmResult,
        properties: {
          'result': reconcile.allArmed ? 'all_armed' : 'degraded',
          'count_bucket': DoselyTelemetry.countBucket(reconcile.armed),
          'error_code': reconcile.failures.isEmpty
              ? null
              : 'platform_schedule_failed',
        },
      );
    }
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
    await const MissedDoseDetector().sweep(
      widget.db,
      snoozeWindow: Duration(minutes: AppSettings.instance.snoozeMinutes),
    );
    if (sync == null) return;
    await sync.syncAll();
    if (syncOwner != null) {
      await SyncStatusStore.instance.refresh(
        ownerId: syncOwner,
        db: widget.db,
        successful: AppSettings.instance.consentCloudBackup,
      );
    }

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
    final taken = await widget.db.takenCountsSinceBaseline(items);
    if (anyRefillLow(items, taken)) {
      unawaited(CareNotifier.instance.refillLow());
    }
  }

  Future<void> _silenceIfRinging() async {
    final n = await NotificationService.instance
        .dismissActiveReminderNotifications();
    if (n == 0) return;
    await NotificationService.instance.reconcile(widget.db);
  }

  Future<void> _reRingUnanswered() async {
    for (final o in _ringIfLeft) {
      if (!doseStillRings(o.status)) continue;
      try {
        await NotificationService.instance.ringDueDoseNow(
          scheduleId: o.item.schedule.id,
          medicine: o.item.medicine,
          scheduledAt: o.scheduledAt,
        );
      } catch (_) {
        // Tests and hosts without the plugin; the in-app list still works.
      }
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
    // Selecting a method is intentionally separate from opening the capture
    // screen: camera and microphone permissions are requested only after the
    // user has made that choice.
    final method = await showModalBottomSheet<_CaptureMethod>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'How do you want to add it?',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Choose one. You can check every detail before saving.',
                style: Theme.of(sheetContext).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              ListTile(
                minTileHeight: 56,
                leading: const Icon(Icons.document_scanner_outlined),
                title: const Text('Scan label'),
                subtitle: const Text('Use your camera to read the label'),
                onTap: () => Navigator.pop(sheetContext, _CaptureMethod.scan),
              ),
              ListTile(
                minTileHeight: 56,
                leading: const Icon(Icons.mic_outlined),
                title: const Text('Speak details'),
                subtitle: const Text('Say the medicine and schedule'),
                onTap: () => Navigator.pop(sheetContext, _CaptureMethod.speak),
              ),
              ListTile(
                minTileHeight: 56,
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Enter manually'),
                subtitle: const Text('Type the details yourself'),
                onTap: () => Navigator.pop(sheetContext, _CaptureMethod.manual),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || method == null) return;

    await DoselyTelemetry.instance.record(
      DoselyEvent.addStarted,
      properties: {'method': method.name},
    );
    if (!mounted) return;
    final navigator = Navigator.of(context);
    switch (method) {
      case _CaptureMethod.scan:
        final ocrText = await navigator.push<String>(
          MaterialPageRoute(builder: (_) => const OcrCaptureScreen()),
        );
        if (ocrText == null || !mounted) return;
        await navigator.push(
          MaterialPageRoute(
            builder: (_) => ReviewEditScreen(ocrText: ocrText, db: widget.db),
          ),
        );
      case _CaptureMethod.speak:
        final transcript = await navigator.push<String>(
          MaterialPageRoute(builder: (_) => const VoiceCaptureScreen()),
        );
        if (transcript == null || !mounted) return;
        await navigator.push(
          MaterialPageRoute(
            builder: (_) =>
                ReviewEditScreen(transcript: transcript, db: widget.db),
          ),
        );
      case _CaptureMethod.manual:
        await navigator.push(
          MaterialPageRoute(builder: (_) => ReviewEditScreen(db: widget.db)),
        );
    }
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
    return ListenableBuilder(
      listenable: ReminderHealthStore.instance,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          toolbarHeight: 64,
          titleSpacing: 20,
          title: const DoselyBrandMark(compact: true),
        ),
        body: StreamBuilder<List<ScheduleWithMedicine>>(
          stream: _schedulesStream,
          builder: (context, scheduleSnap) {
            return StreamBuilder<List<DoseLog>>(
              stream: _doseLogsStream,
              builder: (context, logSnap) {
                return _calendarBody(
                  schedules: scheduleSnap.data ?? const [],
                  logs: logSnap.data ?? const [],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _calendarBody({
    required List<ScheduleWithMedicine> schedules,
    required List<DoseLog> logs,
  }) {
    // A snooze dismissal is tied to the reminder version the user answered.
    // If that reminder is edited while the same occurrence is still visible,
    // clear the old attention suppression so the new definition can surface
    // immediately instead of waiting for the old snooze timeout.
    final scheduleVersions = {
      for (final item in schedules) item.schedule.id: item.schedule.updatedAt,
    };
    final editedScheduleIds = <String>{};
    for (final entry in scheduleVersions.entries) {
      final previous = _attentionScheduleVersions[entry.key];
      if (previous != null && previous != entry.value) {
        editedScheduleIds.add(entry.key);
      }
    }
    if (editedScheduleIds.isNotEmpty) {
      _dismissedAttentionUntil.removeWhere(
        (key, _) => editedScheduleIds.contains(key.split('|').first),
      );
    }
    _attentionScheduleVersions
      ..clear()
      ..addAll(scheduleVersions);
    final now = DateTime.now();
    final snoozeWindow = Duration(minutes: AppSettings.instance.snoozeMinutes);
    final records = <DoseRecord>[
      for (final log in logs) ?DoseRecord.tryFromLog(log),
    ];
    final logIndex = DoseRecordIndex(records);
    final rangeStart = DateTime(now.year, now.month - 18, 1);
    final rangeEnd = DateTime(now.year, now.month + 6, 1);
    final cellMarks = cellMarksForRange(
      items: schedules,
      index: logIndex,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      now: now,
      snoozeWindow: snoozeWindow,
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
      index: logIndex,
      day: _selectedDay,
      now: now,
      snoozeWindow: snoozeWindow,
    );
    final today = calendarDay(now);
    final todayOccs = isSameCalendarDay(_selectedDay, now)
        ? occurrences
        : occurrencesOnDay(
            items: schedules,
            logs: records,
            day: today,
            now: now,
            snoozeWindow: snoozeWindow,
          );
    final yesterdayOccs = occurrencesOnDay(
      items: schedules,
      logs: records,
      day: addCalendarDays(today, -1),
      now: now,
      snoozeWindow: snoozeWindow,
    );
    final allAttention = attentionDoses(
      today: todayOccs,
      yesterday: yesterdayOccs,
    );
    final nowForAttention = DateTime.now();
    _dismissedAttentionUntil.removeWhere(
      (_, until) => !until.isAfter(nowForAttention),
    );
    final attention = [
      for (final occurrence in allAttention)
        if (occurrence.status != DayDoseStatus.snoozed &&
            !(_dismissedAttentionUntil[_attentionKey(occurrence)]?.isAfter(
                  nowForAttention,
                ) ??
                false))
          occurrence,
    ];
    _ringIfLeft = [
      for (final o in attention)
        if (doseStillRings(o.status)) o,
    ];
    // Focus Today once when an unanswered dose first appears. The panel stays
    // available there, but repeatedly requesting the shell to jump back on
    // every rebuild would trap the user on Today and make the other tabs
    // impossible to use until they answered the dose.
    if (attention.isEmpty) {
      _attentionWasPresent = false;
    } else if (attentionNeedsInitialFocus(
      wasPresent: _attentionWasPresent,
      isPresent: true,
    )) {
      _attentionWasPresent = true;
      final jump = widget.onNeedsAttention;
      if (jump != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => jump());
      }
    }
    final next = isSameCalendarDay(_selectedDay, now)
        ? nextUpcomingDose(todayOccs)
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
        if (attention.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: DoselyFadeIn(
                child: DoseAttentionPanel(
                  occurrences: attention,
                  now: now,
                  onMarkTaken: _markTaken,
                  onSnooze: _snooze,
                ),
              ),
            ),
          ),
        if (ReminderHealthStore.instance.hasIssues)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: _ReminderHealthCard(
                onFix: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ReminderReliabilityScreen(db: widget.db),
                  ),
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

  Future<void> _snooze(DayOccurrence occurrence) async {
    final delay = Duration(minutes: AppSettings.instance.snoozeMinutes);
    // Remove the card before waiting on SQLite or the notification plugin.
    // The scheduled one-off reminder remains the way this dose returns to the
    // user's attention after the snooze window.
    if (mounted) {
      setState(() {
        _dismissedAttentionUntil[_attentionKey(occurrence)] = DateTime.now()
            .add(delay);
      });
    }
    try {
      await recordDoseSnoozed(
        widget.db,
        scheduleId: occurrence.item.schedule.id,
        scheduledAt: occurrence.scheduledAt,
        delay: delay,
      );
    } catch (_) {
      // If saving the snooze failed, restore the card so the dose is still
      // actionable instead of silently hiding it.
      if (mounted) {
        setState(
          () => _dismissedAttentionUntil.remove(_attentionKey(occurrence)),
        );
      }
      rethrow;
    }
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

class _ReminderHealthCard extends StatelessWidget {
  const _ReminderHealthCard({required this.onFix});

  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    final issues = ReminderHealthStore.instance.issues.length;
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.notifications_off_outlined,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$issues reminder${issues == 1 ? '' : 's'} need setup',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Your medicine is saved. Check reminder access so the next dose is not missed.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: onFix,
                      child: const Text('Fix reminders'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _attentionKey(DayOccurrence occurrence) =>
    _attentionKeyForValues(occurrence.item.schedule.id, occurrence.scheduledAt);

String _attentionKeyForValues(String scheduleId, DateTime scheduledAt) =>
    '$scheduleId|${scheduledAt.toUtc().toIso8601String()}';

/// Returns true only when an unanswered dose first appears. Rebuilds while it
/// remains unanswered must not steal focus from another tab the user chose.
@visibleForTesting
bool attentionNeedsInitialFocus({
  required bool wasPresent,
  required bool isPresent,
}) => isPresent && !wasPresent;

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
