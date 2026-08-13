import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin wrapper around Supabase Auth — a typed 6-digit email code, not a
/// clickable magic link. A link only completes if opened on the same
/// device the app is installed on; a code has no such requirement, so it
/// works however/wherever the user checks their email.
///
/// Until custom SMTP + the code-only email template are live (blocked on
/// Supabase's free-tier default mailer not allowing template customization
/// — see supabase/config.toml), the email Supabase actually sends still
/// contains the old clickable link. `emailRedirectTo` keeps that link
/// working (deep-links into the app) as a fallback in the meantime; it's
/// harmless to leave once the code-only template goes live, since that
/// template won't render a link at all.
///
/// Google Sign-In needs a Google Cloud OAuth client tied to this app's
/// package name + signing SHA-1, which is a manual one-time console step;
/// wire it in later behind the same interface once that's done.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const _fallbackRedirectUrl = 'dosely://login-callback';

  SupabaseClient get _client => Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;
  bool get isSignedIn => currentUser != null;
  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  Future<void> sendSignInCode(String email) => _client.auth.signInWithOtp(
        email: email,
        emailRedirectTo: _fallbackRedirectUrl,
      );

  Future<void> verifyCode({required String email, required String code}) => _client.auth.verifyOTP(
        email: email,
        token: code,
        type: OtpType.email,
      );

  Future<void> signOut() => _client.auth.signOut();
}
