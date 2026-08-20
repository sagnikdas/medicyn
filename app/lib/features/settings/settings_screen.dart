import 'package:flutter/material.dart';

import '../../core/account_deletion.dart';
import '../../core/app_settings.dart';
import '../../core/privacy_policy.dart';
import '../../data/local/encrypted_database.dart';
import '../auth/auth_service.dart';
import '../care/care_screen.dart';
import '../consent/consent_purpose.dart';
import '../consent/consent_service.dart';
import '../notification_engine/notification_service.dart';

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
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _signingIn = false;
  String? _signInError;

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
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_signedIn) ...[
              Text('Signed in as', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(email, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 24),
            ] else ...[
              OutlinedButton(
                onPressed: _signingIn ? null : _signInWithGoogle,
                child: _signingIn
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Sign in with Google'),
              ),
              if (_signInError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _signInError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
            ],
            Text('Family', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              _signedIn
                  ? 'Let one person help you keep track of your medicines — or help '
                      'someone else with theirs.'
                  : 'Family sharing needs a Google account.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_signedIn) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CareScreen()),
                ),
                icon: const Icon(Icons.people_outline),
                label: const Text('Connect with family'),
              ),
            ],
            const SizedBox(height: 24),
            Text('Text size', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Makes text and buttons throughout the app larger and easier to read.',
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
                      child: Slider(
                        value: scale,
                        min: AppSettings.minTextScale,
                        max: AppSettings.maxTextScale,
                        divisions: AppSettings.textScaleDivisions,
                        label: AppSettings.textScaleLabel(scale),
                        semanticFormatterCallback: (v) => 'Text size ${AppSettings.textScaleLabel(v)}',
                        onChanged: (v) => AppSettings.instance.setTextScale(v),
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
            Text('Theme', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Follows your device by default. Choose Light or Dark to keep '
              'the app on one of them.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            ListenableBuilder(
              listenable: AppSettings.instance,
              builder: (context, _) => SegmentedButton<ThemeMode>(
                segments: [
                  for (final mode in ThemeMode.values)
                    ButtonSegment(value: mode, label: Text(mode.label)),
                ],
                selected: {AppSettings.instance.themeMode},
                onSelectionChanged: (s) => AppSettings.instance.setThemeMode(s.first),
                showSelectedIcon: false,
              ),
            ),
            const SizedBox(height: 20),
            ListenableBuilder(
              listenable: AppSettings.instance,
              builder: (context, _) => SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show medicine names on the lock screen'),
                subtitle: const Text(
                  'Off by default. When off, a locked phone only says a dose is due — not which medicine.',
                ),
                value: AppSettings.instance.showMedicineOnLockScreen,
                onChanged: _setShowMedicineOnLockScreen,
              ),
            ),
            const SizedBox(height: 28),
            Text('Manage what Dosely can do', style: Theme.of(context).textTheme.titleSmall),
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
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(purpose.title),
                        subtitle: Text(purpose.sentence),
                        value: ConsentService.instance.isGranted(purpose),
                        onChanged: (v) => ConsentService.instance.setGranted(purpose, v),
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
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Already-armed alarms still carry the old title and visibility, so a
  /// toggle that only wrote the pref would not take effect until the next
  /// app foreground. Re-arm here so the lock screen matches the switch.
  Future<void> _setShowMedicineOnLockScreen(bool value) async {
    await AppSettings.instance.setShowMedicineOnLockScreen(value);
    try {
      await NotificationService.instance.reconcileFromDisk();
    } catch (_) {
      // Next foreground re-arms; the pref is already stored.
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
    final explained = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
              Text('If you cannot use the app, you can also request deletion at:'),
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
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
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
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
