import 'package:flutter/material.dart';

import '../../core/app_settings.dart';
import 'auth_service.dart';

/// Google sign-in, or local-only so reminders work without an account.
/// Backup and family sharing stay off until the user signs in later.
///
/// The app-level auth gate (see main.dart) moves on by itself once a
/// session exists or [AppSettings.localOnly] is set, so nothing here
/// navigates on success.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _signInWithGoogle() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await AuthService.instance.trySignInWithGoogle();
    if (!mounted) return;
    setState(() {
      _error = error;
      _busy = false;
    });
  }

  Future<void> _useWithoutAccount() => AppSettings.instance.setLocalOnly(true);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        // Scrollable rather than a plain Center+Column: at the largest text
        // size setting this content can outgrow a short screen, and the
        // fixed version clipped instead of scrolling.
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Dosely', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                'Sign in with Google to keep your reminders backed up and on '
                'every device you use.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _busy ? null : _signInWithGoogle,
                child: _busy
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Continue with Google'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _busy ? null : _useWithoutAccount,
                child: const Text('Use without an account'),
              ),
              const SizedBox(height: 12),
              Text(
                'Reminders stay on this phone. Backup and family sharing need Google later.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
