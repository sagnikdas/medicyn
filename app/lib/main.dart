import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_navigation.dart';
import 'core/app_settings.dart';
import 'core/sentry_config.dart';
import 'core/supabase_config.dart';
import 'core/theme.dart';
import 'data/local/database.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/notification_engine/notification_actions.dart';
import 'features/notification_engine/notification_service.dart';
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
      // Must happen before checking the launch response below — the plugin
      // has to be initialized first to answer getNotificationAppLaunchDetails.
      await NotificationService.instance.init();
      final launchResponse = await NotificationService.instance.consumeLaunchNotificationResponse();
      runApp(DoselyApp(launchNotificationResponse: launchResponse));
    },
  );
}

class DoselyApp extends StatefulWidget {
  const DoselyApp({super.key, this.launchNotificationResponse});

  /// Set when the app was launched (cold start) by a notification tap —
  /// see [NotificationService.consumeLaunchNotificationResponse].
  final NotificationResponse? launchNotificationResponse;

  @override
  State<DoselyApp> createState() => _DoselyAppState();
}

class _DoselyAppState extends State<DoselyApp> {
  @override
  void initState() {
    super.initState();
    final response = widget.launchNotificationResponse;
    if (response != null) {
      // The navigator isn't attached yet during this build, so defer until
      // after the first frame — by then navigatorKey.currentState is live.
      WidgetsBinding.instance.addPostFrameCallback((_) => handleNotificationResponse(response));
    }
  }

  @override
  Widget build(BuildContext context) {
    // The listener wraps MaterialApp rather than sitting inside `builder`,
    // because themeMode is a property of MaterialApp itself — the whole app
    // widget has to rebuild for a theme change to take effect. Text size
    // rides along on the same rebuild.
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) => MaterialApp(
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        title: 'Dosely',
        theme: DoselyTheme.light(),
        darkTheme: DoselyTheme.dark(),
        // Light/dark/system, as chosen in Settings; system by default.
        themeMode: AppSettings.instance.themeMode,
        // Applies the user's chosen text size (Settings) to every screen —
        // scales text and, with it, most touch targets.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(AppSettings.instance.textScale),
          ),
          child: child!,
        ),
        home: const _OnboardingGate(),
      ),
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
