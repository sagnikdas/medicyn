import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_navigation.dart';
import 'core/app_settings.dart';
import 'core/device_lock_gate.dart';
import 'core/motion.dart';
import 'core/sentry_config.dart';
import 'core/supabase_init.dart';
import 'core/theme.dart';
import 'core/telemetry.dart';
import 'core/widgets/dosely_motion.dart';
import 'data/local/database.dart';
import 'data/local/database_encryption.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/consent/consent_screen.dart';
import 'features/consent/consent_service.dart';
import 'features/notification_engine/notification_actions.dart';
import 'features/notification_engine/notification_service.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/push/push_service.dart';
import 'features/shell/app_shell.dart';

void main() async {
  // With SentryConfig.dsn empty (the default), SentryFlutter.init disables
  // the SDK entirely — no crash capture, no network calls — so this is a
  // no-op wrapper until a real DSN is configured. The existing init order
  // (Supabase, then AppSettings, then runApp) is preserved unchanged inside
  // the `appRunner`.
  await SentryFlutter.init(
    (options) {
      options.dsn = SentryConfig.dsn;
      options.beforeSend = redactSentryEvent;
    },
    appRunner: () async {
      WidgetsFlutterBinding.ensureInitialized();
      await initializeSupabase();
      await AppSettings.instance.init(
        consentOwnerId:
            Supabase.instance.client.auth.currentUser?.id ?? localOwnerUserId,
      );
      // Must happen before checking the launch response below — the plugin
      // has to be initialized first to answer getNotificationAppLaunchDetails.
      await NotificationService.instance.init();
      // Before runApp, and that matters: PushService.init registers the
      // background message handler, which has to be in place while the main
      // isolate starts up or a message arriving with the app dead has nowhere
      // to go. It no-ops when Firebase isn't configured in this build.
      await PushService.instance.init();
      final launch = await NotificationService.instance
          .consumeLaunchNotificationResponse();
      runApp(DoselyApp(launchNotification: launch));
    },
  );
}

class DoselyApp extends StatefulWidget {
  const DoselyApp({super.key, this.launchNotification});

  /// Set when the app was launched (cold start) by a notification tap —
  /// see [NotificationService.consumeLaunchNotificationResponse].
  final LaunchNotification? launchNotification;

  @override
  State<DoselyApp> createState() => _DoselyAppState();
}

class _DoselyAppState extends State<DoselyApp> {
  @override
  void initState() {
    super.initState();
    final launch = widget.launchNotification;
    if (launch != null) {
      // The navigator isn't attached yet during this build, so defer until
      // after the first frame — by then navigatorKey.currentState is live.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _handleLaunch(launch),
      );
    }
  }

  /// Marks the launch handled only once it has actually been acted on — see
  /// NotificationService.consumeLaunchNotificationResponse for why that
  /// order matters.
  Future<void> _handleLaunch(LaunchNotification launch) async {
    await handleNotificationResponse(launch.response);
    await NotificationService.instance.markLaunchHandled(launch.fingerprint);
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
          child: DeviceLockGate(child: child!),
        ),
        home: const _OnboardingGate(),
      ),
    );
  }
}

/// Shows onboarding once, on first launch only, before anything else —
/// including consent and sign-in. Once the user finishes or skips it, the
/// persisted flag (see AppSettings.hasSeenOnboarding) means this gate goes
/// straight to `_ConsentGate` on every later launch.
class _OnboardingGate extends StatelessWidget {
  const _OnboardingGate();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) {
        // No navigation needed here: OnboardingScreen persists the flag via
        // AppSettings, and that change alone triggers this ListenableBuilder
        // to rebuild into _ConsentGate.
        return DoselySwitcher(
          duration: DoselyMotion.medium,
          child: AppSettings.instance.hasSeenOnboarding
              ? const _ConsentGate(key: ValueKey('consent-gate'))
              : const OnboardingScreen(key: ValueKey('onboarding')),
        );
      },
    );
  }
}

/// Shows the consent screen until the user has recorded a choice — including
/// on existing installs that already skipped onboarding. After Continue the
/// persisted flag (see AppSettings.hasRecordedConsents) means this gate goes
/// straight to `_AuthGate`.
class _ConsentGate extends StatelessWidget {
  const _ConsentGate({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) {
        return DoselySwitcher(
          duration: DoselyMotion.medium,
          child: AppSettings.instance.hasRecordedConsents
              ? const _AuthGate(key: ValueKey('auth-gate'))
              : const ConsentScreen(key: ValueKey('consent')),
        );
      },
    );
  }
}

/// Shows the sign-in screen until there's a session *or* the user chose
/// local-only mode, then the app itself.
/// `currentSession` is checked on every rebuild (including the initial
/// build), and `onAuthStateChange` triggers rebuilds as sign-in/sign-out
/// happen. Choosing "Use without an account" notifies via [AppSettings].
///
/// The database connection is per Google account: a second person signing
/// in on this phone must not inherit the previous person's file. The same
/// person signing back in reopens theirs — reminders stay. Local-only uses
/// the sentinel owner [localOwnerUserId] (`dosely-local.sqlite`); first
/// sign-in on this phone adopts that file when the account has none yet.
class _AuthGate extends StatefulWidget {
  const _AuthGate({super.key});

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  AppDatabase? _db;
  String? _userId;
  var _closing = false;
  String? _syncedConsentUserId;

  @override
  void dispose() {
    unawaited(_db?.close());
    super.dispose();
  }

  /// Returns the open database for [userId], or null while a previous
  /// connection is still closing. First sign-in after local-only *renames*
  /// `dosely-local.sqlite`; that cannot happen while the local file is open.
  AppDatabase? _databaseFor(String userId) {
    if (_db != null && _userId == userId) return _db!;
    if (_db != null && !_closing) {
      _closing = true;
      unawaited(_closeThenRebuild());
      return null;
    }
    if (_closing) return null;
    _userId = userId;
    _db = AppDatabase();
    return _db!;
  }

  Future<void> _closeThenRebuild() async {
    final open = _db;
    _db = null;
    _userId = null;
    await open?.close();
    _closing = false;
    if (mounted) setState(() {});
  }

  void _releaseDatabase() {
    final open = _db;
    _db = null;
    _userId = null;
    _closing = false;
    _syncedConsentUserId = null;
    unawaited(open?.close());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) {
        return StreamBuilder<AuthState>(
          stream: Supabase.instance.client.auth.onAuthStateChange,
          builder: (context, snapshot) {
            final user = Supabase.instance.client.auth.currentUser;
            final owner =
                user?.id ??
                (AppSettings.instance.localOnly ? localOwnerUserId : null);
            final Widget child;
            if (owner == null) {
              _releaseDatabase();
              child = const SignInScreen(key: ValueKey('sign-in'));
            } else {
              if (user != null &&
                  AppSettings.instance.consentOwnerIs(user.id) &&
                  AppSettings.instance.hasRecordedConsents &&
                  _syncedConsentUserId != user.id) {
                _syncedConsentUserId = user.id;
                unawaited(ConsentService.instance.syncToServer());
              }
              final db = _databaseFor(owner);
              if (db == null) {
                child = const Scaffold(
                  key: ValueKey('loading'),
                  body: Center(child: CircularProgressIndicator()),
                );
              } else {
                // No key on AppShell: StreamBuilder rebuilds must update in
                // place so the State that owns the open database is not reset.
                child = AppShell(db: db);
              }
            }
            return DoselySwitcher(duration: DoselyMotion.medium, child: child);
          },
        );
      },
    );
  }
}
