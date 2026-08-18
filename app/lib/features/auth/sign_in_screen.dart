import 'package:flutter/material.dart';

import 'auth_service.dart';

/// One button. Google is the only way in — the email one-time-code flow was
/// removed along with the custom SMTP sender behind it.
///
/// The app-level auth gate (see main.dart) moves on by itself once a
/// session exists, so nothing here navigates on success.
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
    try {
      await AuthService.instance.signInWithGoogle();
      // Success moves the app on via the auth-state stream in main.dart.
    } on GoogleSignInFailure catch (e) {
      // Backing out of the account picker isn't a failure — showing an
      // error for it would make a deliberate action look broken.
      setState(() => _error = e.isCancellation ? null : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
