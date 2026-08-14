import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_settings.dart';
import '../auth/auth_service.dart';

/// Deliberately sparse — there's almost nothing to configure by design.
/// Notification sound/vibration follow the OS channel settings (opened via
/// the system link below) rather than a duplicate in-app setting. The two
/// real controls are text size — the single highest-impact accessibility
/// lever for elderly users, and it needs no extra "large touch targets"
/// toggle alongside it since buttons/fields size around their text — and
/// theme, which stays on the device's own light/dark setting unless the
/// user overrides it here.
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
