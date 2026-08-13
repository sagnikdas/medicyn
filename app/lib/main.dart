import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_settings.dart';
import 'core/supabase_config.dart';
import 'core/theme.dart';
import 'data/local/database.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/reminders_home/home_screen.dart';

final appDatabase = AppDatabase();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );
  await AppSettings.instance.init();
  runApp(const DoselyApp());
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
      home: const _AuthGate(),
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
