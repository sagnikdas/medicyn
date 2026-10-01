import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_settings.dart';
import '../../core/locale_dates.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../core/widgets/medicyn_background.dart';
import '../../data/local/database.dart';
import '../../data/remote/today_care_sync_service.dart';
import '../auth/auth_service.dart';
import '../notification_engine/notification_service.dart';
import '../settings/settings_screen.dart';
import 'day_dose_style.dart';
import 'day_occurrences.dart';
import 'reminder_copy.dart';
import 'today_care_editor.dart';
import 'today_care_store.dart';

/// Only Home's Android branch mounts this screen. Shared medicine views and
/// the iOS home retain their existing layout and behavior.
class AndroidTodayScreen extends StatefulWidget {
  const AndroidTodayScreen({
    super.key,
    required this.db,
    required this.now,
    required this.occurrences,
    required this.earlier,
    required this.scrollController,
    required this.onAddMedicine,
    required this.onTaken,
    required this.onSnooze,
    required this.onHistory,
    this.healthNotice,
    this.missedDoseNudge,
  });

  final AppDatabase db;
  final DateTime now;
  final List<DayOccurrence> occurrences;
  final List<DayOccurrence> earlier;
  final ScrollController scrollController;
  final Future<void> Function() onAddMedicine;
  final Future<void> Function(DayOccurrence) onTaken;
  final Future<void> Function(DayOccurrence) onSnooze;
  final ValueChanged<DayOccurrence> onHistory;
  final Widget? healthNotice;

  /// The gentle "you missed a dose" nudge computed by Home, shown for this
  /// user's own doses only — never the caregiver's separate care alert.
  final Widget? missedDoseNudge;

  @override
  State<AndroidTodayScreen> createState() => _AndroidTodayScreenState();
}

class _AndroidTodayScreenState extends State<AndroidTodayScreen>
    with WidgetsBindingObserver {
  late final _store = TodayCareStore(widget.db);
  late final _care = _store.watch();
  final _notifications = TodayCareNotifications();
  bool _alertIssue = false;
  bool _reconciling = false;
  bool _reconcileAgain = false;
  bool _syncing = false;
  bool _syncInFlight = false;
  bool _syncAgain = false;
  bool _syncFailed = false;
  int _pendingSync = 0;
  Timer? _syncTimer;
  StreamSubscription<List<TodayCareReminder>>? _careChanges;

  bool get _cloudReady =>
      AuthService.instance.isSignedIn &&
      AppSettings.instance.consentCloudBackup &&
      AppSettings.instance.consentOwnerId ==
          AuthService.instance.currentUser?.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _careChanges = widget.db.select(widget.db.todayCareReminders).watch().listen((
      rows,
    ) {
      if (!mounted) return;
      setState(
        () => _pendingSync = rows.where((row) => row.pendingSync).length,
      );
      // Includes server edits, completions and deletions arriving after Home's
      // initial restore, so notifications follow the current account data.
      unawaited(_reconcile());
    }, onError: (Object _) {});
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(_syncCare());
      }
    });
    unawaited(_syncCare());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncTimer?.cancel();
    unawaited(_careChanges?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_reconcile());
      unawaited(_syncCare());
    }
  }

  Future<void> _syncCare({bool immediate = false}) async {
    if (!mounted || !_cloudReady) return;
    if (_syncInFlight) {
      _syncAgain = true;
      return;
    }
    _syncInFlight = true;
    // Background polls usually find nothing to do and finish quickly; only
    // surface the "Syncing…" banner once a sync is still running past this
    // grace period, so routine polling doesn't flash the UI every 30s. A
    // user tapping "retry" on a visible failure is different: they need to
    // see their tap register right away, not wonder for half a second
    // whether it landed.
    Timer? showSyncingTimer;
    if (immediate) {
      setState(() => _syncing = true);
    } else {
      showSyncingTimer = Timer(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _syncing = true);
      });
    }
    var success = false;
    try {
      success = await TodayCareSyncService(widget.db).sync();
    } catch (_) {
      // The local queue survives until connectivity is restored.
    } finally {
      showSyncingTimer?.cancel();
      _syncInFlight = false;
      if (mounted) {
        setState(() {
          _syncing = false;
          _syncFailed = !success;
        });
        if (_syncAgain) {
          _syncAgain = false;
          unawaited(_syncCare());
        }
      }
    }
  }

  void _openSettings() => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => SettingsScreen(db: widget.db)));

  bool _requireCloud() {
    if (_cloudReady) return true;
    _message(
      'Other care needs sign-in and cloud backup so your plans are saved to your account.',
      action: SnackBarAction(label: 'Settings', onPressed: _openSettings),
    );
    return false;
  }

  Future<void> _reconcile() async {
    if (_reconciling) {
      _reconcileAgain = true;
      return;
    }
    _reconciling = true;
    try {
      final reminders = await _care.first;
      final armed = await _notifications.reconcile(reminders);
      if (mounted) setState(() => _alertIssue = !armed);
    } catch (_) {
      if (mounted) setState(() => _alertIssue = true);
    } finally {
      _reconciling = false;
      if (_reconcileAgain && mounted) {
        _reconcileAgain = false;
        unawaited(_reconcile());
      }
    }
  }

  Future<void> _retryAlerts() async {
    try {
      final granted = await NotificationService.instance
          .requestNotificationPermission();
      if (!granted) {
        _message(
          'Enable notifications for Medicyn in Android Settings, then return to Today.',
        );
      }
      await _reconcile();
    } catch (_) {
      _message('Could not check notification access. Please try again.');
    }
  }

  void _message(String text, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), action: action));
  }

  Future<void> _add() async {
    final choice = await showTodayAddMenu(context);
    if (choice == null || !mounted) return;
    if (choice == 'medicine') {
      await widget.onAddMedicine();
    } else {
      await _edit(kind: TodayCareKind.fromName(choice));
    }
  }

  Future<void> _edit({TodayCareKind? kind, TodayCareReminder? existing}) async {
    if (!_requireCloud()) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => TodayCareEditor(
        kind: kind ?? TodayCareKind.fromName(existing!.kind),
        existing: existing,
        onSave: _save,
        onDelete: _remove,
      ),
    );
  }

  Future<void> _save(TodayCareReminder reminder) async {
    if (!_requireCloud()) throw StateError('Cloud backup is required');
    await _store.save(reminder);
    unawaited(_syncCare());
    var armed = false;
    try {
      if (reminder.reminderMinutes != null) {
        await NotificationService.instance.requestNotificationPermission();
      }
      armed = await _notifications.schedule(reminder, newlySaved: true);
    } catch (_) {
      // The saved agenda entry remains available for retry on foreground.
    }
    if (!mounted) return;
    setState(() => _alertIssue = !armed);
    _message(
      armed
          ? 'Reminder saved. Check cloud sync status in Today.'
          : 'Saved. Notifications need attention to send an alert.',
    );
  }

  Future<void> _remove(TodayCareReminder reminder) async {
    if (!_requireCloud()) throw StateError('Cloud backup is required');
    await _store.remove(reminder.id);
    unawaited(_syncCare());
    try {
      await _notifications.cancel(reminder.id);
    } catch (_) {
      // Reconciliation retries notification cleanup independently of sync.
    }
    _message(
      'Reminder removed',
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => unawaited(_restore(reminder)),
      ),
    );
  }

  Future<void> _restore(TodayCareReminder reminder) async {
    try {
      await _save(reminder);
    } catch (_) {
      _message('Could not restore the reminder. Please try again.');
    }
  }

  Future<void> _done(TodayCareReminder reminder) async {
    if (!_requireCloud()) return;
    await _store.save(reminder.copyWith(completed: true));
    unawaited(_syncCare());
    try {
      await _notifications.cancel(reminder.id);
    } catch (_) {
      // A notification failure must not prevent persisting completion.
    }
    _message(
      'Marked done',
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => unawaited(_restore(reminder)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TodayCareReminder>>(
      stream: _care,
      builder: (context, snapshot) => TodayAgenda(
        now: widget.now,
        occurrences: widget.occurrences,
        earlier: widget.earlier,
        care: snapshot.data ?? const [],
        careLoading: !snapshot.hasData && !snapshot.hasError,
        careError: snapshot.hasError,
        alertIssue: _alertIssue,
        onRetryAlerts: _retryAlerts,
        scrollController: widget.scrollController,
        onAdd: _add,
        onTaken: widget.onTaken,
        onSnooze: widget.onSnooze,
        onHistory: widget.onHistory,
        onEditCare: (reminder) => _edit(existing: reminder),
        onCompleteCare: _done,
        healthNotice: widget.healthNotice,
        missedDoseNudge: widget.missedDoseNudge,
        careSyncNotice:
            _syncing ||
                _syncFailed ||
                _pendingSync > 0 ||
                (!_cloudReady && (snapshot.data?.isNotEmpty ?? false))
            ? ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _syncing
                      ? Icons.cloud_sync_outlined
                      : Icons.cloud_off_outlined,
                ),
                title: Text(
                  !_cloudReady
                      ? 'Care plans need cloud backup'
                      : _syncing
                      ? 'Syncing care plans…'
                      : _pendingSync > 0
                      ? '$_pendingSync care change${_pendingSync == 1 ? '' : 's'} waiting to sync'
                      : 'Could not refresh care plans',
                ),
                subtitle: Text(
                  !_cloudReady
                      ? 'Sign in and enable cloud backup in Settings.'
                      : _syncing
                      ? 'Saving your care plans to your account.'
                      : _pendingSync > 0
                      ? 'These changes are only on this phone. Tap to retry.'
                      : 'Your saved care plans are available. Tap to retry.',
                ),
                onTap: _cloudReady
                    ? () => _syncCare(immediate: true)
                    : _openSettings,
              )
            : null,
      ),
    );
  }
}

/// Presentation is separate from storage so the daily agenda can be exercised
/// at phone/tablet sizes and large text without native notification plugins.
class TodayAgenda extends StatelessWidget {
  const TodayAgenda({
    super.key,
    required this.now,
    required this.occurrences,
    required this.care,
    required this.onAdd,
    required this.onTaken,
    required this.onSnooze,
    required this.onHistory,
    required this.onEditCare,
    required this.onCompleteCare,
    this.earlier = const [],
    this.scrollController,
    this.healthNotice,
    this.missedDoseNudge,
    this.careLoading = false,
    this.careError = false,
    this.careSyncNotice,
    this.alertIssue = false,
    this.onRetryAlerts,
  });

  final DateTime now;
  final List<DayOccurrence> occurrences;
  final List<DayOccurrence> earlier;
  final List<TodayCareReminder> care;
  final VoidCallback onAdd;
  final Future<void> Function(DayOccurrence) onTaken;
  final Future<void> Function(DayOccurrence) onSnooze;
  final ValueChanged<DayOccurrence> onHistory;
  final ValueChanged<TodayCareReminder> onEditCare;
  final Future<void> Function(TodayCareReminder) onCompleteCare;
  final ScrollController? scrollController;
  final Widget? healthNotice;

  /// The gentle "you missed a dose" nudge computed by Home, shown for this
  /// user's own doses only — never the caregiver's separate care alert.
  final Widget? missedDoseNudge;
  final bool careLoading;
  final bool careError;
  final Widget? careSyncNotice;
  final bool alertIssue;
  final VoidCallback? onRetryAlerts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final todayCare = care
        .where((r) => isSameCalendarDay(r.scheduledAt.toLocal(), now))
        .toList();
    final pendingDoses = occurrences
        .where((o) => o.status != DayDoseStatus.taken)
        .toList();
    final pendingCare = todayCare.where((r) => !r.completed).toList();
    final completed =
        occurrences.length -
        pendingDoses.length +
        todayCare.length -
        pendingCare.length;
    final total = occurrences.length + todayCare.length;
    final entries = <({DateTime at, Widget child})>[
      for (final dose in pendingDoses)
        (
          at: dose.scheduledAt,
          child: _TodayDoseRow(
            key: ValueKey(
              'dose-${dose.item.schedule.id}-${dose.scheduledAt.toUtc()}',
            ),
            occurrence: dose,
            now: now,
            onTaken: onTaken,
            onSnooze: onSnooze,
            onHistory: onHistory,
          ),
        ),
      for (final reminder in pendingCare)
        (
          at: reminder.scheduledAt.toLocal(),
          child: _TodayCareRow(
            key: ValueKey(reminder.id),
            reminder: reminder,
            now: now,
            onEdit: () => onEditCare(reminder),
            onDone: () => onCompleteCare(reminder),
          ),
        ),
    ]..sort((a, b) => a.at.compareTo(b.at));
    final futureCare =
        care
            .where(
              (r) =>
                  !r.completed &&
                  DateUtils.dateOnly(
                    r.scheduledAt.toLocal(),
                  ).isAfter(DateUtils.dateOnly(now)),
            )
            .toList()
          ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    final pastCare = care
        .where(
          (r) =>
              !r.completed &&
              DateUtils.dateOnly(
                r.scheduledAt.toLocal(),
              ).isBefore(DateUtils.dateOnly(now)),
        )
        .toList();
    final pastDoses = earlier
        .where((o) => o.status != DayDoseStatus.taken)
        .toList();

    return Scaffold(
      // No backgroundColor override: every other tab gets its warmth from
      // the theme's own scheme.surface (scaffoldBackgroundColor). This
      // screen previously flattened it to a near-white FAFAF6 in light
      // mode, which read as cold and out of step with the rest of the app.
      body: MedicynGradientBackground(
        child: SafeArea(
          bottom: false,
          child: CustomScrollView(
            controller: scrollController,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      MedicynGlassHeader(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _dateLabel(now).toUpperCase(),
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: scheme.primary,
                                letterSpacing: 1.1,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Today',
                                    style: theme.textTheme.headlineLarge
                                        ?.copyWith(
                                          fontSize: 38,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: -1.4,
                                          color: scheme.primary,
                                        ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                TextButton.icon(
                                  onPressed: onAdd,
                                  icon: const Icon(Icons.add, size: 20),
                                  label: const Text('Add'),
                                  style: TextButton.styleFrom(
                                    backgroundColor: scheme.primary.withValues(
                                      alpha: 0.07,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 12,
                                    ),
                                    shape: const StadiumBorder(),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'A little care, one thing at a time.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (total > 0) ...[
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${entries.length} remaining',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                            Text(
                              '$completed of $total done',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TweenAnimationBuilder<double>(
                          tween: Tween(end: completed / total),
                          duration: MedicynMotion.duration(
                            context,
                            MedicynMotion.medium,
                          ),
                          builder: (_, value, _) => LinearProgressIndicator(
                            value: value,
                            minHeight: 3,
                            borderRadius: BorderRadius.circular(4),
                            backgroundColor: scheme.primary.withValues(
                              alpha: 0.08,
                            ),
                            semanticsLabel:
                                '$completed of $total reminders completed',
                          ),
                        ),
                      ],
                      if (missedDoseNudge != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 24),
                          child: missedDoseNudge!,
                        ),
                      if (healthNotice != null)
                        Padding(
                          padding: EdgeInsets.only(
                            top: missedDoseNudge != null ? 16 : 24,
                          ),
                          child: healthNotice!,
                        ),
                      if (careSyncNotice != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: careSyncNotice!,
                        ),
                      if (alertIssue &&
                          care.any(
                            (r) => !r.completed && r.reminderMinutes != null,
                          ))
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.notifications_off_outlined,
                            ),
                            title: const Text('Care alerts need attention'),
                            subtitle: const Text(
                              'Your plans are saved. Check notification access.',
                            ),
                            onTap: onRetryAlerts,
                            trailing: const Icon(Icons.refresh),
                          ),
                        ),
                      const SizedBox(height: 32),
                      const _SectionLabel('YOUR DAY'),
                      const SizedBox(height: 12),
                      AnimatedSize(
                        duration: MedicynMotion.duration(
                          context,
                          MedicynMotion.medium,
                        ),
                        curve: MedicynMotion.standard,
                        alignment: Alignment.topCenter,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (entries.isEmpty)
                              _QuietDay(
                                now: now,
                                completed: completed > 0,
                                loading: careLoading,
                                error: careError,
                              )
                            else ...[
                              for (final entry in entries) entry.child,
                              if (careLoading)
                                const LinearProgressIndicator(minHeight: 2),
                              if (careError)
                                const Text(
                                  'Care reminders could not be loaded. Reopen Today to try again.',
                                ),
                            ],
                          ],
                        ),
                      ),
                      if (pastDoses.isNotEmpty || pastCare.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Theme(
                          data: theme.copyWith(
                            dividerColor: Colors.transparent,
                          ),
                          child: ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            childrenPadding: EdgeInsets.zero,
                            title: Text(
                              'Earlier · ${pastDoses.length + pastCare.length} unanswered',
                              style: theme.textTheme.bodyMedium,
                            ),
                            children: [
                              for (final dose in pastDoses)
                                _TodayDoseRow(
                                  key: ValueKey(
                                    'earlier-${dose.item.schedule.id}-${dose.scheduledAt}',
                                  ),
                                  occurrence: dose,
                                  now: now,
                                  onTaken: onTaken,
                                  onSnooze: onSnooze,
                                  onHistory: onHistory,
                                ),
                              for (final reminder in pastCare)
                                _TodayCareRow(
                                  key: ValueKey(reminder.id),
                                  reminder: reminder,
                                  now: now,
                                  onEdit: () => onEditCare(reminder),
                                  onDone: () => onCompleteCare(reminder),
                                ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      if (futureCare.isNotEmpty) ...[
                        const _SectionLabel('COMING UP'),
                        const SizedBox(height: 12),
                        for (final reminder in futureCare.take(3))
                          _TodayCareRow(
                            key: ValueKey(reminder.id),
                            reminder: reminder,
                            now: now,
                            onEdit: () => onEditCare(reminder),
                          ),
                        if (futureCare.length > 3)
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: Text(
                              'View ${futureCare.length - 3} more',
                              style: theme.textTheme.bodyMedium,
                            ),
                            children: [
                              for (final reminder in futureCare.skip(3))
                                _TodayCareRow(
                                  key: ValueKey(reminder.id),
                                  reminder: reminder,
                                  now: now,
                                  onEdit: () => onEditCare(reminder),
                                ),
                            ],
                          ),
                        const SizedBox(height: 24),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  // Bare text here would sit directly on the gradient ground (see
  // MedicynGlassHeader), so give it a frosted backing for contrast.
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: MedicynGlassHeader(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          letterSpacing: 1.4,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  );
}

/// Wording for the common case: nothing scheduled today, nothing broken. A
/// few equally calm variants so the screen someone opens every single day
/// doesn't read as a canned system message on day 200. Picked by the date
/// (stable all day, changes tomorrow) rather than randomly per rebuild,
/// which would make the heading flicker between unrelated phrasings as the
/// rest of the screen updates.
const _quietDayVariants = [
  (
    title: 'Room to take it easy',
    subtitle: 'Nothing scheduled today. Add a reminder when you need one.',
  ),
  (
    title: 'A quiet start today',
    subtitle: "Nothing's due right now — add a reminder whenever you need one.",
  ),
  (
    title: 'Nothing on the chart today',
    subtitle: "No reminders scheduled. Add one whenever you're ready.",
  ),
  (
    title: 'A little breathing room',
    subtitle: "Nothing's due today. Add a reminder when you need one.",
  ),
];

class _QuietDay extends StatelessWidget {
  const _QuietDay({
    required this.now,
    required this.completed,
    required this.loading,
    required this.error,
  });
  final DateTime now;
  final bool completed;
  final bool loading;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quietDay = _quietDayVariants[now.day % _quietDayVariants.length];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            loading
                ? Icons.more_horiz
                : error
                ? Icons.cloud_off_outlined
                : completed
                ? Icons.check_circle_outline_rounded
                : Icons.wb_sunny_outlined,
            size: 32,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            loading
                ? 'Loading your day…'
                : error
                ? 'Care reminders unavailable'
                : completed
                ? 'All clear for today'
                : quietDay.title,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            loading
                ? 'Your care reminders will appear here.'
                : error
                ? 'Reopen Today to try again.'
                : completed
                ? 'Everything is checked off. Enjoy the rest of your day.'
                : quietDay.subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayDoseRow extends StatelessWidget {
  const _TodayDoseRow({
    super.key,
    required this.occurrence,
    required this.now,
    required this.onTaken,
    required this.onSnooze,
    required this.onHistory,
  });
  final DayOccurrence occurrence;
  final DateTime now;
  final Future<void> Function(DayOccurrence) onTaken;
  final Future<void> Function(DayOccurrence) onSnooze;
  final ValueChanged<DayOccurrence> onHistory;

  @override
  Widget build(BuildContext context) {
    final medicine = occurrence.item.medicine;
    final status = occurrence.status;
    final today = isSameCalendarDay(occurrence.scheduledAt, now);
    final label = !today
        ? 'Yesterday · not recorded'
        : switch (status) {
            DayDoseStatus.pending => 'Due now',
            DayDoseStatus.upcoming => 'Later today',
            DayDoseStatus.snoozed => 'Snoozed',
            DayDoseStatus.missed => 'Missed',
            DayDoseStatus.notRecorded => 'Not recorded',
            DayDoseStatus.taken => 'Taken',
          };
    // Just the dose amount — the notes field can carry a full label's worth
    // of parsed text (ingredients, physician instructions), which belongs on
    // the medicine's own detail screen, not clogging every row of Today's
    // agenda. See _AgendaRow's title/subtitle for the line clamp that also
    // protects this row against an unusually long drug name.
    final detail = medicine.doseAmount.trim();
    final record = occurrence.record;
    final snoozedUntil = status == DayDoseStatus.snoozed && record != null
        ? record.loggedAt.toLocal().add(
            Duration(minutes: AppSettings.instance.snoozeMinutes),
          )
        : null;
    return _AgendaRow(
      at: occurrence.scheduledAt,
      now: now,
      title: medicineTitle(medicine),
      subtitle: detail,
      label: label,
      icon: Icons.medication_outlined,
      doseStatus: status,
      active: status == DayDoseStatus.pending,
      snoozedUntil: snoozedUntil,
      actionLabel: 'Taken',
      onAction: () => onTaken(occurrence),
      secondaryLabel: doseCanSnooze(status) && today ? 'Snooze' : null,
      onSecondary: doseCanSnooze(status) && today
          ? () => onSnooze(occurrence)
          : null,
      onOpen: () => onHistory(occurrence),
    );
  }
}

class _TodayCareRow extends StatelessWidget {
  const _TodayCareRow({
    super.key,
    required this.reminder,
    required this.now,
    required this.onEdit,
    this.onDone,
  });
  final TodayCareReminder reminder;
  final DateTime now;
  final VoidCallback onEdit;
  final Future<void> Function()? onDone;

  @override
  Widget build(BuildContext context) {
    final kind = TodayCareKind.fromName(reminder.kind);
    return _AgendaRow(
      at: reminder.scheduledAt.toLocal(),
      now: now,
      title: reminder.title,
      subtitle: [
        if (reminder.location.isNotEmpty) reminder.location,
        if (reminder.notes.isNotEmpty) reminder.notes,
      ].join(' · '),
      label: kind.label,
      icon: kind.icon,
      onOpen: onEdit,
      actionLabel: onDone == null ? null : 'Done',
      onAction: onDone,
    );
  }
}

/// Leading mark on an agenda row. A care reminder (no [status]) keeps the
/// plain primary-tinted icon; a dose row renders the same status ring/glyph
/// treatment as the chart's per-row mark (see `_StatusAvatar` in
/// day_dose_list.dart) so Today reads status by shape, matching the rest of
/// the app rather than relying on the caption text alone — including the
/// same "popping in with a slight overshoot" transition DESIGN.md promises
/// for a status change, since this is the screen that promise is actually
/// experienced on.
class _AgendaAvatar extends StatefulWidget {
  const _AgendaAvatar({required this.icon, required this.active, this.status});

  final IconData icon;
  final bool active;
  final DayDoseStatus? status;

  @override
  State<_AgendaAvatar> createState() => _AgendaAvatarState();
}

/// A persistent controller rather than a keyed widget swap, matching
/// `_StatusAvatarState` in day_dose_list.dart: the glyph [Icon] stays one
/// long-lived element across a status change while [_pop] scales it from
/// underneath — see that class's doc for the real crash a keyed rebuild
/// caused on hardware.
class _AgendaAvatarState extends State<_AgendaAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    // Built eagerly here, not as `late final` field initializers: a care
    // row (no status) never touches _pop/_scale in build(), and a lazy
    // initializer deferred that far would only fire inside dispose(),
    // constructing a controller against an already-deactivated element.
    _pop = AnimationController(
      vsync: this,
      duration: MedicynMotion.medium,
      value: 1,
    );
    _scale = CurvedAnimation(parent: _pop, curve: Curves.easeOutBack);
  }

  @override
  void didUpdateWidget(covariant _AgendaAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) {
      if (MedicynMotion.reduce(context)) {
        _pop.value = 1;
      } else {
        _pop.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = widget.status;
    if (status == null) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.primary.withValues(alpha: widget.active ? 0.12 : 0.08),
          boxShadow: widget.active
              ? MedicynTheme.glow(scheme.primary, opacity: 0.3, blur: 14)
              : null,
        ),
        child: Icon(
          widget.icon,
          size: 22,
          color: widget.active ? scheme.primary : scheme.onSurfaceVariant,
        ),
      );
    }
    final color = DayDoseStyle.color(context, status);
    final due =
        status == DayDoseStatus.pending || status == DayDoseStatus.upcoming;
    final filled = status == DayDoseStatus.taken;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled
            ? color
            : due
            ? color.withValues(alpha: 0.12)
            : scheme.surfaceContainerHigh,
        border: filled
            ? null
            : Border.all(color: color.withValues(alpha: 0.6), width: 2),
        boxShadow: filled
            ? MedicynTheme.glow(color, opacity: 0.45, blur: 16)
            : null,
      ),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: Icon(
          DayDoseStyle.glyph(status),
          size: 22,
          color: filled ? scheme.onPrimary : color,
        ),
      ),
    );
  }
}

class _AgendaRow extends StatefulWidget {
  const _AgendaRow({
    required this.at,
    required this.now,
    required this.title,
    required this.subtitle,
    required this.label,
    required this.icon,
    required this.onOpen,
    this.active = false,
    this.doseStatus,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
    this.snoozedUntil,
  });
  final DateTime at;
  final DateTime now;
  final String title;
  final String subtitle;
  final String label;
  final IconData icon;
  final bool active;

  /// When set, the leading avatar renders [DayDoseStyle]'s glyph+color for
  /// this status instead of a fixed icon — so Taken/Missed/Snoozed/Not
  /// recorded read by shape, not just by the caption text beside them.
  final DayDoseStatus? doseStatus;
  final String? actionLabel;
  final Future<void> Function()? onAction;
  final String? secondaryLabel;
  final Future<void> Function()? onSecondary;
  final VoidCallback onOpen;

  /// When set, shows a "Snoozed until HH:mm" line — matching the treatment
  /// on the Plan card (see _SnoozeStatus in reminder_card.dart) — instead of
  /// leaving the person to infer it from [label] alone.
  final DateTime? snoozedUntil;

  @override
  State<_AgendaRow> createState() => _AgendaRowState();
}

class _AgendaRowState extends State<_AgendaRow> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save this change. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = isSameCalendarDay(widget.at, widget.now);
    final time = TimeOfDay.fromDateTime(widget.at).format(context);
    final snoozedUntil = widget.snoozedUntil;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          // Frosted, not flat opaque — matches AmbientCard's glass treatment
          // over the gradient ground.
          color: scheme.surfaceContainerLowest.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(16),
          boxShadow: MedicynTheme.ambientShadow,
          border: widget.active
              ? Border.all(
                  color: scheme.primary.withValues(alpha: 0.4),
                  width: 1.5,
                )
              : Border.all(color: Colors.white.withValues(alpha: 0.24)),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AgendaAvatar(
              icon: widget.icon,
              active: widget.active,
              status: widget.doseStatus,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: _busy ? null : widget.onOpen,
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: double.infinity,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${today ? time : '${_dateLabel(widget.at, weekday: false)} · $time'}  ·  ${widget.label}',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: widget.active
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (widget.subtitle.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Text(
                              widget.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                height: 1.5,
                              ),
                            ),
                          ],
                          if (snoozedUntil != null) ...[
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.snooze,
                                  size: 15,
                                  color: scheme.tertiary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Snoozed until ${TimeOfDay.fromDateTime(snoozedUntil).format(context)}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.tertiary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (widget.onAction == null)
                            const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                  if (widget.onAction != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Semantics(
                            label:
                                '${widget.actionLabel}: ${widget.title}, $time',
                            child: FilledButton.tonalIcon(
                              onPressed: _busy
                                  ? null
                                  : () => _run(widget.onAction!),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 44),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                backgroundColor: scheme.primary.withValues(
                                  alpha: 0.09,
                                ),
                                foregroundColor: scheme.primary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: Icon(
                                _busy ? Icons.more_horiz : Icons.check_rounded,
                                size: 18,
                              ),
                              // FittedBox rather than relying on the label
                              // being short enough: at a large system text
                              // size (this app's accessibility text-scale
                              // setting can push it well past 100%) even
                              // "Taken" plus its icon can outgrow the
                              // available half-width, and an ellipsis there
                              // reads as broken rather than adaptive. This
                              // scales the label down to whatever actually
                              // fits instead of ever clipping it.
                              label: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(widget.actionLabel!, maxLines: 1),
                              ),
                            ),
                          ),
                        ),
                        if (widget.onSecondary != null) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: Semantics(
                              label:
                                  '${widget.secondaryLabel}: ${widget.title}, $time',
                              // Filled (tonal), not outlined — a bare outline
                              // on this card's warm, low-contrast background
                              // read as "not filled in" rather than as a
                              // deliberate secondary action.
                              child: FilledButton.tonalIcon(
                                onPressed: _busy
                                    ? null
                                    : () => _run(widget.onSecondary!),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(0, 44),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  backgroundColor: scheme.secondaryContainer,
                                  foregroundColor: scheme.onSecondaryContainer,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                icon: const Icon(Icons.snooze, size: 18),
                                label: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    widget.secondaryLabel!,
                                    maxLines: 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _dateLabel(DateTime date, {bool weekday = true}) {
  final prefix = weekday ? '${localeWeekdayName(date)}, ' : '';
  return '$prefix${localeDayMonthAbbr(date)}';
}
