import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/account_deletion.dart';
import '../../core/app_settings.dart';
import '../../core/privacy_policy.dart';
import '../../core/widgets/medicyn_chrome.dart';
import '../../core/widgets/medicyn_layout.dart';
import '../../core/widgets/medicyn_motion.dart';
import '../../data/export/adherence_export_service.dart';
import '../../data/export/data_export_service.dart';
import '../../data/local/database.dart';
import '../../data/local/encrypted_database.dart';
import '../../data/remote/sync_service.dart';
import '../../data/remote/sync_status.dart';
import '../auth/auth_service.dart';
import '../care/care_screen.dart';
import '../care/care_service.dart';
import '../care/dose_feed_screen.dart';
import '../consent/consent_purpose.dart';
import '../consent/consent_service.dart';
import '../emergency/emergency_card_screen.dart';
import '../notification_engine/notification_service.dart';
import '../notification_engine/reminder_reliability_screen.dart';

/// Deliberately sparse — there's almost nothing to configure by design.
/// Notification sound/vibration follow the OS channel settings (opened via
/// the system link below) rather than a duplicate in-app setting. The
/// controls that do live here are text size — the single highest-impact
/// accessibility lever for elderly users, and it needs no extra "large
/// touch targets" toggle alongside it since buttons/fields size around
/// their text — theme, which stays on the device's own light/dark setting
/// unless the user overrides it here, and whether a locked phone may show
/// which medicine is due.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.db,
    this.embedded = false,
    this.active = true,
  });

  final AppDatabase db;

  /// True when this screen is the Profile tab, so it draws the Stitch
  /// header instead of a "Settings" app bar.
  final bool embedded;

  /// The shell keeps Profile mounted in an IndexedStack. Reset the settings
  /// list when the tab becomes active so it always opens at the beginning.
  final bool active;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _signingIn = false;
  String? _signInError;
  bool _exporting = false;
  bool _sharingReport = false;
  late final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    unawaited(_refreshSyncStatus());
  }

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        _scrollController.jumpTo(0);
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool get _signedIn => AuthService.instance.isSignedIn;

  Future<void> _signInWithGoogle() async {
    setState(() {
      _signingIn = true;
      _signInError = null;
    });
    final error = await AuthService.instance.trySignInWithGoogle();
    if (!mounted) return;
    setState(() {
      _signInError = error;
      _signingIn = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final email = AuthService.instance.currentUser?.email ?? '';
    final name = email.contains('@') ? email.split('@').first : email;
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: MedicynContent(
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              if (widget.embedded) ...[
                const SizedBox(height: 8),
                MedicynFadeIn(
                  child: Center(
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 48,
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.secondaryContainer,
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onSecondaryContainer,
                          // No foregroundImage: a third-party account photo
                          // (Google's default is a saturated, uncontrolled
                          // color) would break the single-accent rule on the
                          // one screen meant to be its home. The initial
                          // below is the only avatar treatment.
                          child: Text(
                            (name.isEmpty ? 'D' : name.substring(0, 1))
                                .toUpperCase(),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _signedIn
                              ? (name.isEmpty ? email : name)
                              : 'On this phone',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _signedIn
                              ? email
                              : 'Reminders stay on this device until you sign in.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),
              ] else if (_signedIn) ...[
                MedicynFadeIn(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Signed in as',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        email,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ] else ...[
                OutlinedButton(
                  onPressed: _signingIn ? null : _signInWithGoogle,
                  child: MedicynSwitcher(
                    child: _signingIn
                        ? const SizedBox(
                            key: ValueKey(true),
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'Sign in with Google',
                            key: ValueKey(false),
                          ),
                  ),
                ),
                if (_signInError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _signInError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
              ],
              if (widget.embedded && !_signedIn) ...[
                OutlinedButton(
                  onPressed: _signingIn ? null : _signInWithGoogle,
                  child: MedicynSwitcher(
                    child: _signingIn
                        ? const SizedBox(
                            key: ValueKey(true),
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'Sign in with Google',
                            key: ValueKey(false),
                          ),
                  ),
                ),
                if (_signInError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _signInError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
              ],
              MedicynFadeIn(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Emergency card',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ProfileMenuRow(
                      icon: Icons.local_hospital,
                      // The app's one "needs attention" red (same as
                      // DayDoseStyle's Missed mark), not the usual teal —
                      // this is the one row on the screen meant to read as
                      // urgent rather than routine.
                      iconBackgroundColor: Theme.of(context).colorScheme.error,
                      iconColor: Theme.of(context).colorScheme.onError,
                      title: 'Emergency card',
                      subtitle:
                          'Blood group, allergies, conditions, and your medicines — for a first responder or new clinician.',
                      onTap: () {
                        // A second tap can land before the first push's
                        // transition covers this row -- without this guard
                        // it queues a second push that races the first
                        // route's still-in-flight animation (visible
                        // ghosting, and a hit-test crash on a render object
                        // that hasn't been laid out yet).
                        final route = ModalRoute.of(context);
                        if (route != null && !route.isCurrent) return;
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => EmergencyCardScreen(db: widget.db),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Family',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    IgnorePointer(
                      ignoring: !_signedIn,
                      child: Opacity(
                        opacity: _signedIn ? 1 : 0.6,
                        child: ProfileMenuRow(
                          icon: Icons.people_outline,
                          title: 'Connect with family',
                          subtitle: _signedIn
                              ? 'Let one person help you keep track of your medicines — or help someone else with theirs.'
                              : 'Family sharing needs a Google account.',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => CareScreen(db: widget.db),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const _FamilyFeedLink(),
                    const SizedBox(height: 24),
                    ListenableBuilder(
                      listenable: SyncStatusStore.instance,
                      builder: (context, _) => _BackupStatusCard(
                        signedIn: _signedIn,
                        onRetry: _retrySync,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Reminder reliability',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ProfileMenuRow(
                      icon: Icons.notifications_active_outlined,
                      title: 'Check reminder access',
                      subtitle:
                          'See whether notifications and timing are ready, then send a test reminder.',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              ReminderReliabilityScreen(db: widget.db),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Dose responses',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ListenableBuilder(
                      listenable: AppSettings.instance,
                      builder: (context, _) => DropdownButtonFormField<int>(
                        initialValue: AppSettings.instance.snoozeMinutes,
                        decoration: const InputDecoration(
                          labelText: 'Snooze duration',
                        ),
                        items: [
                          for (final minutes in AppSettings.snoozeOptions)
                            DropdownMenuItem(
                              value: minutes,
                              child: Text('$minutes minutes'),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            unawaited(_setSnoozeMinutes(value));
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Appearance',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '100% is the default size. Drag right to make text and buttons larger.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    // Nothing previews the setting better than the screen you're on:
                    // the slider rescales the whole app live as it's dragged, this
                    // row included.
                    ListenableBuilder(
                      listenable: AppSettings.instance,
                      builder: (context, _) {
                        final scale = AppSettings.instance.textScale;
                        return Row(
                          children: [
                            Expanded(
                              child: Slider.adaptive(
                                value: scale,
                                min: AppSettings.minTextScale,
                                max: AppSettings.maxTextScale,
                                divisions: AppSettings.textScaleDivisions,
                                label: AppSettings.textScaleLabel(scale),
                                semanticFormatterCallback: (v) =>
                                    'Text size ${AppSettings.textScaleLabel(v)}',
                                onChanged: (v) =>
                                    AppSettings.instance.setTextScale(v),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              AppSettings.textScaleLabel(scale),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Theme',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Follows your device by default. Choose Light or Dark to keep '
                      'the app on one of them.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    ListenableBuilder(
                      listenable: AppSettings.instance,
                      builder: (context, _) => SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<ThemeMode>(
                          segments: [
                            for (final mode in ThemeMode.values)
                              ButtonSegment(
                                value: mode,
                                label: Text(mode.label, maxLines: 1),
                              ),
                          ],
                          selected: {AppSettings.instance.themeMode},
                          onSelectionChanged: (s) =>
                              AppSettings.instance.setThemeMode(s.first),
                          showSelectedIcon: false,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    ListenableBuilder(
                      listenable: AppSettings.instance,
                      builder: (context, _) => SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Show medicine names on the lock screen',
                        ),
                        subtitle: const Text(
                          'Off by default. When off, a locked phone only says a dose is due — not which medicine.',
                        ),
                        value: AppSettings.instance.showMedicineOnLockScreen,
                        onChanged: _setShowMedicineOnLockScreen,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'Your data',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'This is a copy of the data Medicyn holds about you (Art. 15/20). '
                      'Other requests are answered within one month (Art. 12(3)) by email '
                      'contact@doezly.com.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _exportBusy ? null : _downloadMyData,
                      icon: MedicynSwitcher(
                        child: _exporting
                            ? const SizedBox(
                                key: ValueKey('json-busy'),
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.download_outlined,
                                key: ValueKey('json'),
                              ),
                      ),
                      label: Text(
                        _exporting ? 'Preparing…' : 'Download my data',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'A four-week PDF of medicines and what was marked taken — '
                      'for a clinic visit, not a full copy of your account.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _exportBusy ? null : _shareDoctorReport,
                      icon: MedicynSwitcher(
                        child: _sharingReport
                            ? const SizedBox(
                                key: ValueKey('pdf-busy'),
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.picture_as_pdf_outlined,
                                key: ValueKey('pdf'),
                              ),
                      ),
                      label: Text(
                        _sharingReport ? 'Preparing…' : 'Share with my doctor',
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'Manage what Medicyn can do',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Turning any of these off takes effect straight away, the same as turning them on.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    ListenableBuilder(
                      listenable: AppSettings.instance,
                      builder: (context, _) {
                        return Column(
                          children: [
                            for (final purpose in ConsentPurpose.values)
                              SwitchListTile.adaptive(
                                contentPadding: EdgeInsets.zero,
                                title: Text(purpose.title),
                                subtitle: Text(purpose.sentence),
                                value: ConsentService.instance.isGranted(
                                  purpose,
                                ),
                                onChanged: (v) =>
                                    _onConsentChanged(context, purpose, v),
                              ),
                          ],
                        );
                      },
                    ),
                    if (_signedIn) ...[
                      const SizedBox(height: 28),
                      OutlinedButton(
                        onPressed: () => _confirmSignOut(context),
                        child: const Text('Sign out'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => _confirmDeleteAccount(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                        child: const Text('Delete account'),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => openPrivacyPolicy(context),
                      child: Text(
                        'Privacy policy',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              decoration: TextDecoration.underline,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _exportBusy => _exporting || _sharingReport;

  Future<void> _downloadMyData() async {
    if (_exportBusy) return;
    setState(() => _exporting = true);
    try {
      final box = context.findRenderObject() as RenderBox?;
      await DataExportService(widget.db).exportAndShare(
        sharePositionOrigin: box != null
            ? box.localToGlobal(Offset.zero) & box.size
            : null,
      );
    } catch (e) {
      if (!mounted) return;
      await showAdaptiveDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog.adaptive(
          title: const Text('Could not export'),
          content: const Text(
            'Your data could not be prepared right now. Check your storage and try again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _shareDoctorReport() async {
    if (_exportBusy) return;
    setState(() => _sharingReport = true);
    try {
      final box = context.findRenderObject() as RenderBox?;
      await AdherenceExportService(widget.db).exportAndShare(
        sharePositionOrigin: box != null
            ? box.localToGlobal(Offset.zero) & box.size
            : null,
      );
    } catch (e) {
      if (!mounted) return;
      await showAdaptiveDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog.adaptive(
          title: const Text('Could not prepare the report'),
          content: const Text(
            'The PDF could not be prepared right now. Check your storage and try again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _sharingReport = false);
    }
  }

  Future<void> _refreshSyncStatus() async {
    final ownerId = AppSettings.instance.consentOwnerId;
    if (ownerId == null) return;
    await SyncStatusStore.instance.refresh(ownerId: ownerId, db: widget.db);
  }

  Future<void> _retrySync() async {
    final ownerId = AppSettings.instance.consentOwnerId;
    if (!_signedIn || ownerId == null) return;
    await SyncStatusStore.instance.markSyncing(ownerId);
    try {
      await SyncService(widget.db).syncAll();
      await SyncStatusStore.instance.refresh(
        ownerId: ownerId,
        db: widget.db,
        successful: AppSettings.instance.consentCloudBackup,
      );
    } catch (_) {
      await SyncStatusStore.instance.refresh(
        ownerId: ownerId,
        db: widget.db,
        errorCode: 'sync_failed',
      );
    }
  }

  /// Already-armed alarms still carry the old title and visibility, so a
  /// toggle that only wrote the pref would not take effect until the next
  /// app foreground. Re-arm here so the lock screen matches the switch.
  Future<void> _setShowMedicineOnLockScreen(bool value) async {
    await AppSettings.instance.setShowMedicineOnLockScreen(value);
    try {
      await NotificationService.instance.reconcile(widget.db);
    } catch (_) {
      // Next foreground re-arms; the pref is already stored.
    }
  }

  Future<void> _setSnoozeMinutes(int minutes) async {
    await AppSettings.instance.setSnoozeMinutes(minutes);
    // Notification action labels and payload details are stored when the
    // alarm is armed. Reconcile so an already-armed notification does not
    // continue offering the previous duration.
    try {
      await NotificationService.instance.reconcile(widget.db);
    } catch (_) {
      // The preference is already saved; the next foreground reconcile will
      // update any existing alarms.
    }
  }

  /// Cloud backup consent is what gates the missed-dose push in
  /// HomeScreen._bootstrap (no push means nothing for the server to
  /// announce), but the Care screens read link status alone and keep saying
  /// "Connected" regardless. Turning it off while a caregiver is actually
  /// linked would silently stop the one thing that screen is telling them is
  /// still working — worth a stop, unlike every other purpose here, which
  /// really does take effect with nothing else watching.
  Future<void> _onConsentChanged(
    BuildContext context,
    ConsentPurpose purpose,
    bool value,
  ) async {
    if (purpose != ConsentPurpose.cloudBackup || value) {
      await ConsentService.instance.setGranted(purpose, value);
      return;
    }
    final me = AuthService.instance.currentUser?.id;
    CareLink? link;
    try {
      link = await CareService.instance.currentLink();
    } catch (_) {
      // Can't confirm either way without a network round-trip that just
      // failed — fail open rather than block turning consent off.
    }
    final linkedAsPatient =
        link != null &&
        link.status == CareLinkStatus.active &&
        link.patientId == me;
    if (!linkedAsPatient) {
      await ConsentService.instance.setGranted(purpose, value);
      return;
    }
    if (!context.mounted) return;
    final confirmed = await showAdaptiveDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog.adaptive(
        title: const Text('Turn off cloud backup?'),
        content: const Text(
          "Your caregiver won't be told if you miss a dose while this is "
          'off, even though their screen will still say Connected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Turn off'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ConsentService.instance.setGranted(purpose, value);
    }
  }

  /// Signing out is a one-tap action sitting at the end of a screen people
  /// scroll through for the text size control, and getting back in means a
  /// round-trip through Google's account picker — enough friction that a
  /// mis-tap is worth a confirm step.
  Future<void> _confirmSignOut(BuildContext context) async {
    // Captured before the await so the dialog's result doesn't have to be
    // paired with a `context.mounted` check afterwards.
    final navigator = Navigator.of(context);
    final confirmed = await showAdaptiveDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog.adaptive(
        title: const Text('Sign out?'),
        content: const Text(
          "You'll need to sign in with Google again to get back in. "
          'Your reminders stay on this phone for this Google account.',
        ),
        actions: [
          // Plain TextButtons on purpose: the app theme stretches
          // Filled/OutlinedButton to full width, which a dialog's action
          // row can't lay out.
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    // Null when the dialog is dismissed by tapping outside or the back
    // button — both mean "no".
    if (confirmed != true) return;
    await AuthService.instance.signOut();
    navigator.popUntil((r) => r.isFirst);
  }

  /// Two dialogs on purpose: Delete account sits at the bottom of Settings
  /// next to Sign out, and a single tap must not erase the Google-linked
  /// backup. The second step is another explicit "Delete my account"
  /// (error-coloured) rather than typing a phrase — easier to read and
  /// hit for the people this app is for.
  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final navigator = Navigator.of(context);
    final explained = await showAdaptiveDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog.adaptive(
        title: const Text('Delete your account?'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This permanently deletes your Google-linked backup, your '
                'medicines, your dose history, and any family link. This '
                'cannot be undone.',
              ),
              SizedBox(height: 16),
              Text(
                'If you cannot use the app, you can also request deletion at:',
              ),
              SizedBox(height: 8),
              SelectableText(deleteAccountWebUrl),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (explained != true) return;
    if (!context.mounted) return;

    final confirmed = await showAdaptiveDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog.adaptive(
        title: const Text('Permanently delete?'),
        content: const Text(
          'Your account and all of this data will be deleted now. This cannot '
          'be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete my account'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Captured before sign-out: AuthGate closes the database when the
    // session ends, and wipe must still know which per-user file to remove.
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null || userId.isEmpty) return;

    if (!context.mounted) return;
    showAdaptiveDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog.adaptive(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Expanded(child: Text('Deleting your account…')),
            ],
          ),
        ),
      ),
    );

    Object? failure;
    try {
      await requestServerAccountDeletion();
    } catch (e) {
      failure = e;
    }

    if (navigator.canPop()) navigator.pop();

    if (failure != null) {
      if (!context.mounted) return;
      await showAdaptiveDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog.adaptive(
          title: const Text('Could not delete account'),
          content: Text('$failure'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    // Sign out first so AuthGate closes the open database, then wipe this
    // account's file. Wiping while the connection is still open fails on
    // some platforms. The Keystore encryption key is left in place —
    // another account on this phone still needs it.
    await AuthService.instance.signOut();
    await wipeEncryptedDatabaseForUser(userId);
    navigator.popUntil((r) => r.isFirst);
  }
}

class _BackupStatusCard extends StatelessWidget {
  const _BackupStatusCard({required this.signedIn, required this.onRetry});

  final bool signedIn;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final status = SyncStatusStore.instance;
    final scheme = Theme.of(context).colorScheme;
    final enabled = status.backupEnabled;
    final waiting = status.pendingWork > 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  enabled
                      ? (waiting
                            ? Icons.cloud_upload_outlined
                            : Icons.cloud_done_outlined)
                      : Icons.cloud_off_outlined,
                  color: enabled ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Backup',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (signedIn && enabled)
                  TextButton(
                    onPressed: status.syncing ? null : onRetry,
                    child: const Text('Retry'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(status.summary, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(
              enabled
                  ? 'Your local reminders keep working even while backup is waiting.'
                  : signedIn
                  ? 'Turn on Cloud backup below when you want another device to restore this data.'
                  : 'Sign in when you want to enable backup on another device.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Link to the shared care-link feed, moved here from Insights: this is
/// about the family relationship itself, not personal adherence analytics,
/// so it belongs next to "Connect with family" rather than at the foot of
/// a stats page. Renders nothing until signed in with an active link —
/// including the plain not-signed-in case — so callers can place it
/// unconditionally.
class _FamilyFeedLink extends StatefulWidget {
  const _FamilyFeedLink();

  @override
  State<_FamilyFeedLink> createState() => _FamilyFeedLinkState();
}

class _FamilyFeedLinkState extends State<_FamilyFeedLink> {
  CareLink? _link;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (AuthService.instance.currentUser == null) return;
    try {
      final link = await CareService.instance.currentLink();
      if (!mounted) return;
      setState(() => _link = link);
    } catch (_) {
      // The rest of Settings still works without a care link.
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = AuthService.instance.currentUser;
    final link = _link;
    if (me == null || link == null || link.status != CareLinkStatus.active) {
      return const SizedBox.shrink();
    }
    final amPatient = link.isPatient(me.id);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ProfileMenuRow(
        icon: Icons.query_stats_outlined,
        title: amPatient ? 'What they see' : "Their week's doses",
        subtitle: 'The same feed both sides of a care link share.',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DoseFeedScreen(
              patientId: link.patientId,
              viewingOwnData: amPatient,
            ),
          ),
        ),
      ),
    );
  }
}
