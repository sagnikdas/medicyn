import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_settings.dart';
import '../auth/auth_service.dart';

/// Deliberately sparse — there's almost nothing to configure by design.
/// Notification sound/vibration follow the OS channel settings (opened via
/// the system link below) rather than a duplicate in-app setting. The one
/// real control is text size — the single highest-impact accessibility
/// lever for elderly users, and it needs no extra "large touch targets"
/// toggle alongside it since buttons/fields size around their text.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (email.isNotEmpty) ...[
              Text('Signed in as', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(email, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 24),
            ],
            Text('Text size', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Makes text and buttons throughout the app larger and easier to read.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            ListenableBuilder(
              listenable: AppSettings.instance,
              builder: (context, _) => SegmentedButton<TextSize>(
                segments: [
                  for (final size in TextSize.values)
                    ButtonSegment(value: size, label: Text(size.label)),
                ],
                selected: {AppSettings.instance.textSize},
                onSelectionChanged: (s) => AppSettings.instance.setTextSize(s.first),
                showSelectedIcon: false,
              ),
            ),
            const SizedBox(height: 28),
            OutlinedButton(
              onPressed: () => _confirmSignOut(context),
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }

  /// Signing out is a one-tap action sitting at the end of a screen people
  /// scroll through for the text size control, and getting back in means
  /// waiting on an emailed code — enough friction that a mis-tap is worth
  /// a confirm step.
  Future<void> _confirmSignOut(BuildContext context) async {
    // Captured before the await so the dialog's result doesn't have to be
    // paired with a `context.mounted` check afterwards.
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          "You'll need a new sign-in code emailed to you to get back in. "
          'Your reminders stay on this device either way.',
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
