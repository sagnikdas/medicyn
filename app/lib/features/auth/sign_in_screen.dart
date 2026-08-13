import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException, AuthRetryableFetchException;

import 'auth_service.dart';

/// Email + a 6-digit code — no clickable link, so it works no matter which
/// device or mail client the user reads the email on. The app-level auth
/// gate (see main.dart) moves on automatically once verifyCode succeeds.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

enum _Step { email, code }

class _SignInScreenState extends State<SignInScreen> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  _Step _step = _Step.email;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.signInWithGoogle();
      // Success moves the app on via the auth-state stream in main.dart.
    } catch (e) {
      // Most likely cause right now: no Google Cloud OAuth client has been
      // registered for this app yet (see AuthService.signInWithGoogle doc).
      // Email + code below always works regardless, so fail quietly here.
      setState(() => _error = "Google Sign-In isn't set up yet — please use email instead.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter a valid email');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.sendSignInCode(email);
      setState(() => _step = _Step.code);
    } catch (e) {
      // Distinguish the cases that actually confused us while building this
      // screen: a rate limit was previously swallowed into this same
      // "check your connection" message, which sent us hunting for a
      // network problem that didn't exist.
      String message;
      if (e is AuthRetryableFetchException) {
        message = 'Could not send a code. Check your connection and try again.';
      } else if (e is AuthException && e.code == 'over_email_send_rate_limit') {
        message = "You've requested a few too many codes — wait a few minutes and try again.";
      } else if (e is AuthException) {
        message = 'Could not send a code right now — try again in a moment.';
      } else {
        message = 'Could not send a code. Check your connection and try again.';
      }
      setState(() => _error = message);
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.verifyCode(email: _emailController.text.trim(), code: code);
      // Success moves the app on via the auth-state stream in main.dart.
    } catch (e) {
      setState(() => _error = 'That code didn\'t work. Check it and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        // A plain Center+Column here overflows once the keyboard shrinks the
        // available height — this screen has grown too tall to always fit
        // above it (Google button + divider + field + button), especially
        // at larger text-size settings. Scrolling is what actually keeps
        // every field reachable no matter how much room the keyboard leaves.
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Dosely', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                _step == _Step.email
                    ? 'Enter your email to get a sign-in code — no password needed.'
                    : 'Enter the code we sent to ${_emailController.text.trim()}.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              if (_step == _Step.email) ..._emailStep() else ..._codeStep(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _emailStep() {
    return [
      OutlinedButton(
        onPressed: _busy ? null : _signInWithGoogle,
        child: const Text('Continue with Google'),
      ),
      const SizedBox(height: 16),
      Text(
        'or sign in with email',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _emailController,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        decoration: const InputDecoration(hintText: 'you@example.com'),
        onSubmitted: (_) => _sendCode(),
      ),
      const SizedBox(height: 16),
      if (_error != null) ...[
        Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 12),
      ],
      FilledButton(
        onPressed: _busy ? null : _sendCode,
        child: _busy
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Text('Send sign-in code'),
      ),
    ];
  }

  List<Widget> _codeStep() {
    return [
      TextField(
        controller: _codeController,
        keyboardType: TextInputType.number,
        autofillHints: const [AutofillHints.oneTimeCode],
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall,
        decoration: const InputDecoration(hintText: '000000'),
        onSubmitted: (_) => _verifyCode(),
      ),
      const SizedBox(height: 16),
      if (_error != null) ...[
        Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 12),
      ],
      FilledButton(
        onPressed: _busy ? null : _verifyCode,
        child: _busy
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Text('Verify & sign in'),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: _busy
            ? null
            : () => setState(() {
                  _step = _Step.email;
                  _codeController.clear();
                  _error = null;
                }),
        child: const Text('Use a different email'),
      ),
    ];
  }
}
