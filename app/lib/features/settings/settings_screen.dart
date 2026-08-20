import 'package:flutter/material.dart';

import '../../core/app_settings.dart';
import '../../core/privacy_policy.dart';
import '../auth/auth_service.dart';
import '../care/care_screen.dart';
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
            if (_signedIn) ...[
              const SizedBox(height: 28),
              OutlinedButton(
                onPressed: () => _confirmSignOut(context),
                child: const Text('Sign out'),
              ),
            ],
            const SizedBox(height: 12),
            TextButton(
              onPressed: openPrivacyPolicy,
              child: const Text('Privacy policy'),
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
}
