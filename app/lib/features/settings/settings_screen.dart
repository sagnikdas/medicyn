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
              onPressed: () async {
                await AuthService.instance.signOut();
                if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
              },
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}
