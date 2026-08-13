import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_settings.dart';
import 'core/sentry_config.dart';
import 'core/supabase_config.dart';
import 'core/theme.dart';
import 'data/local/database.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/reminders_home/home_screen.dart';

final appDatabase = AppDatabase();

void main() async {
  // With SentryConfig.dsn empty (the default), SentryFlutter.init disables
  // the SDK entirely — no crash capture, no network calls — so this is a
  // no-op wrapper until a real DSN is configured. The existing init order
  // (Supabase, then AppSettings, then runApp) is preserved unchanged inside
  // the `appRunner`.
  await SentryFlutter.init(
    (options) {
      options.dsn = SentryConfig.dsn;
    },
    appRunner: () async {
      WidgetsFlutterBinding.ensureInitialized();
      await Supabase.initialize(
        url: SupabaseConfig.url,
        publishableKey: SupabaseConfig.publishableKey,
      );
      await AppSettings.instance.init();
      runApp(const DoselyApp());
    },
  );
}

class DoselyApp extends StatelessWidget {
  const DoselyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dosely',
      theme: DoselyTheme.light(),
      darkTheme: DoselyTheme.dark(),
      // Applies the user's chosen text size (Settings) to every screen —
      // scales text and, with it, most touch targets.
      builder: (context, child) => ListenableBuilder(
        listenable: AppSettings.instance,
        builder: (context, _) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(AppSettings.instance.textSize.scaleFactor),
          ),
          child: child!,
        ),
      ),
      home: const _OnboardingGate(),
    );
  }
}

/// Shows onboarding once, on first launch only, before anything else —
/// including sign-in. Once the user finishes or skips it, the persisted
/// flag (see AppSettings.hasSeenOnboarding) means this gate goes straight
/// to `_AuthGate` on every later launch.
class _OnboardingGate extends StatelessWidget {
  const _OnboardingGate();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) {
        if (AppSettings.instance.hasSeenOnboarding) {
          return const _AuthGate();
        }
        // No navigation needed here: OnboardingScreen already persists the
        // flag via AppSettings before calling this back, and that change
        // alone triggers this ListenableBuilder to rebuild into _AuthGate.
        return OnboardingScreen(onFinished: () {});
      },
    );
  }
}

/// Shows the sign-in screen until there's a session, then the app itself.
/// `currentSession` is checked on every rebuild (including the initial
/// build), and `onAuthStateChange` triggers rebuilds as sign-in/sign-out
/// happen — including the magic-link deep link completing.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final signedIn = Supabase.instance.client.auth.currentSession != null;
        return signedIn ? HomeScreen(db: appDatabase) : const SignInScreen();
      },
    );
  }
}
