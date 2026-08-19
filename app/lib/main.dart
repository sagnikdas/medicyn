import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_navigation.dart';
import 'core/app_settings.dart';
import 'core/sentry_config.dart';
import 'core/supabase_init.dart';
import 'core/theme.dart';
import 'data/local/database.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/notification_engine/notification_actions.dart';
import 'features/notification_engine/notification_service.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/push/push_service.dart';
import 'features/reminders_home/home_screen.dart';

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
      await initializeSupabase();
      await AppSettings.instance.init();
      // Must happen before checking the launch response below — the plugin
      // has to be initialized first to answer getNotificationAppLaunchDetails.
      await NotificationService.instance.init();
      // Before runApp, and that matters: PushService.init registers the
      // background message handler, which has to be in place while the main
      // isolate starts up or a message arriving with the app dead has nowhere
      // to go. It no-ops when Firebase isn't configured in this build.
      await PushService.instance.init();
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
        // No navigation needed here: OnboardingScreen persists the flag via
        // AppSettings, and that change alone triggers this ListenableBuilder
        // to rebuild into _AuthGate.
        return const OnboardingScreen();
      },
    );
  }
}

/// Shows the sign-in screen until there's a session, then the app itself.
/// `currentSession` is checked on every rebuild (including the initial
/// build), and `onAuthStateChange` triggers rebuilds as sign-in/sign-out
/// happen.
///
/// The database connection is per Google account: a second person signing
/// in on this phone must not inherit the previous person's file. The same
/// person signing back in reopens theirs — reminders stay.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  AppDatabase? _db;
  String? _userId;

  @override
  void dispose() {
    unawaited(_db?.close());
    super.dispose();
  }

  AppDatabase _databaseFor(String userId) {
    if (_db != null && _userId == userId) return _db!;
    unawaited(_db?.close());
    _userId = userId;
    _db = AppDatabase();
    return _db!;
  }

  void _releaseDatabase() {
    final open = _db;
    _db = null;
    _userId = null;
    unawaited(open?.close());
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final user = Supabase.instance.client.auth.currentUser;
        if (user == null) {
          _releaseDatabase();
          return const SignInScreen();
        }
        return HomeScreen(db: _databaseFor(user.id));
      },
    );
  }
}
