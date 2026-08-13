import 'package:google_sign_in/google_sign_in.dart';
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
/// Google Sign-In (see [signInWithGoogle]) is a second, faster path for
/// users who already have a Google account on their phone — it needs a
/// Google Cloud OAuth client tied to this app's package name + signing
/// SHA-1, which is a manual one-time console step. Until that's done,
/// calling it throws; callers should show a friendly message rather than
/// surface the raw error. The email+code flow above is unaffected either
/// way and remains the primary, always-working method.
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

  /// The Web OAuth client ID from Google Cloud Console (see README's Auth
  /// section) — `google_sign_in` needs this as `serverClientId` so the ID
  /// token's audience matches what Supabase's Google provider verifies
  /// against. Left blank until that manual Console step is done.
  static const _googleServerClientId = '';

  bool _googleSignInInitialized = false;

  /// Triggers the native Google sign-in flow and exchanges the resulting
  /// ID token for a Supabase session via `GoTrueClient.signInWithIdToken`
  /// (gotrue 2.27.1, as pulled in by supabase_flutter 2.17.1).
  ///
  /// `GoogleSignIn.initialize` must run exactly once before any other call
  /// on the instance, hence the guard flag.
  ///
  /// iOS note: once the iOS platform folder exists, it will additionally
  /// need a `GIDClientID` entry + URL scheme registered in Info.plist.
  Future<void> signInWithGoogle() async {
    if (_googleServerClientId.isEmpty) {
      // No Google Cloud OAuth client has been registered yet — fail fast
      // with a clear cause instead of letting the native SDK throw an
      // opaque platform error. See the class doc and README's Auth section.
      throw StateError('Google Sign-In is not configured yet.');
    }
    if (!_googleSignInInitialized) {
      await GoogleSignIn.instance.initialize(serverClientId: _googleServerClientId);
      _googleSignInInitialized = true;
    }
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const AuthException('Google did not return an ID token.');
    }
    await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
    );
  }

  Future<void> signOut() => _client.auth.signOut();
}
