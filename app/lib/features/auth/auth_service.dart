import 'dart:async';
import 'dart:io' show Platform;

import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_settings.dart';
import '../../core/google_auth_config.dart';
import '../care/care_service.dart';
import '../consent/consent_service.dart';
import '../push/push_service.dart';

/// Raised when Google sign-in doesn't produce a session. [message] is
/// written to be shown to the user as-is; [isCancellation] is true when the
/// user simply backed out of the account picker, which the UI should treat
/// as a non-event rather than an error.
class GoogleSignInFailure implements Exception {
  const GoogleSignInFailure(this.message, {this.isCancellation = false});
  final String message;
  final bool isCancellation;

  @override
  String toString() => message;
}

/// Thin wrapper around Supabase Auth. Google is the only sign-in method —
/// the previous email one-time-code flow was removed deliberately, along
/// with the custom SMTP sender it depended on.
///
/// The flow is native, not web-based: [GoogleSignIn] shows the on-device
/// account picker, and the resulting ID token is exchanged for a Supabase
/// session via `GoTrueClient.signInWithIdToken` (gotrue 2.27.1, as pulled
/// in by supabase_flutter 2.17.1). Nothing opens a browser and no
/// deep-link/redirect URL is involved, which is why the app no longer
/// registers a `dosely://` scheme.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  SupabaseClient get _client => Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;
  bool get isSignedIn => currentUser != null;
  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  bool _googleSignInInitialized = false;

  /// `GoogleSignIn.initialize` must run exactly once before any other call
  /// on the instance, hence the guard flag.
  Future<void> _ensureGoogleInitialized() async {
    if (_googleSignInInitialized) return;
    await GoogleSignIn.instance.initialize(
      serverClientId: GoogleAuthConfig.serverClientId,
      // Android identifies the app by package name + signing SHA-1 rather
      // than a client ID, so this is iOS-only. Passing an empty string
      // would be treated as a real (invalid) client ID, hence the null.
      clientId: Platform.isIOS && GoogleAuthConfig.iosClientId.isNotEmpty
          ? GoogleAuthConfig.iosClientId
          : null,
    );
    _googleSignInInitialized = true;
  }

  /// Runs the native account picker and exchanges the resulting ID token
  /// for a Supabase session. Throws [GoogleSignInFailure] on every failure
  /// path, with a message already fit to show the user.
  Future<void> signInWithGoogle() async {
    if (!GoogleAuthConfig.isConfigured) {
      throw const GoogleSignInFailure(
        "Sign-in isn't configured in this build. See the Auth section of the README.",
      );
    }
    try {
      await _ensureGoogleInitialized();
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        // Practically always a console misconfiguration rather than a
        // transient fault: the native SDK only omits the ID token when the
        // serverClientId it was given isn't a valid Web client for this
        // project.
        throw const GoogleSignInFailure(
          "Google didn't return a sign-in token. The app's Google configuration looks incomplete.",
        );
      }
      await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
      );
      // Local-only is the unbundled path; a live Google session means
      // backup and Care Link are available, so drop the flag.
      await AppSettings.instance.setLocalOnly(false);
      // Best-effort, and awaited only so the name is present by the time the
      // first screen renders. A failure here costs a display name, not a
      // session, so it never throws.
      await CareService.instance.upsertOwnProfile();
      // Not awaited: a device that fails to register receives no care alerts,
      // which is a degraded link rather than a failed sign-in, and every
      // foreground retries it.
      unawaited(PushService.instance.registerToken());
      unawaited(ConsentService.instance.syncToServer());
    } on GoogleSignInFailure {
      rethrow;
    } on GoogleSignInException catch (e) {
      throw GoogleSignInFailure(_describe(e), isCancellation: e.code == GoogleSignInExceptionCode.canceled);
    } on AuthException catch (e) {
      // The token was fine but Supabase rejected it. Overwhelmingly this is
      // the Android OAuth client ID missing from the provider's authorized
      // client list, which surfaces as an audience/issuer complaint.
      throw GoogleSignInFailure(
        'Google signed you in, but this app could not complete sign-in. (${e.message})',
      );
    } catch (e) {
      throw GoogleSignInFailure('Could not sign in with Google. Check your connection and try again. ($e)');
    }
  }

  /// Runs [signInWithGoogle] and returns a message fit to show, or null on
  /// success or when the user backed out of the account picker.
  Future<String?> trySignInWithGoogle() async {
    try {
      await signInWithGoogle();
      return null;
    } on GoogleSignInFailure catch (e) {
      return e.isCancellation ? null : e.message;
    }
  }

  /// Maps the native SDK's failure codes onto messages that say something
  /// actionable. The configuration cases are called out separately because
  /// they're permanent — retrying, which is what a generic "try again"
  /// message invites, can never fix them.
  static String _describe(GoogleSignInException e) {
    switch (e.code) {
      case GoogleSignInExceptionCode.canceled:
        return 'Sign-in cancelled.';
      case GoogleSignInExceptionCode.interrupted:
      case GoogleSignInExceptionCode.uiUnavailable:
        return 'Sign-in was interrupted. Please try again.';
      case GoogleSignInExceptionCode.clientConfigurationError:
      case GoogleSignInExceptionCode.providerConfigurationError:
        return "This app's Google sign-in setup is incomplete — it needs the release signing "
            'certificate registered in Google Cloud Console. (${e.description ?? e.code.name})';
      case GoogleSignInExceptionCode.userMismatch:
      case GoogleSignInExceptionCode.unknownError:
        return 'Could not sign in with Google. (${e.description ?? e.code.name})';
    }
  }

  /// Clears the Supabase session *and* the cached Google account, so the
  /// next sign-in shows the account picker rather than silently reusing
  /// whoever signed in last — otherwise "sign out" looks broken to anyone
  /// switching accounts.
  Future<void> signOut() async {
    // Before the session is cleared, because the delete is authorised by row-
    // level security against the signed-in user. A phone handed back should
    // stop receiving the previous account's alerts now, not whenever FCM next
    // reissues its token.
    await PushService.instance.unregisterToken();
    if (_googleSignInInitialized) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {
        // Best-effort: never let the Google SDK block the Supabase sign-out
        // below, which is the part that actually ends the session.
      }
    }
    await _client.auth.signOut();
  }
}
