/// The Google Cloud OAuth client IDs this app signs in with.
///
/// None of these are secrets — an OAuth *client ID* is public by design and
/// ships inside every Android/iOS binary that uses it. (The matching client
/// *secret* is a secret, but it never comes near this app: only Supabase
/// holds it, configured in the dashboard.) So embedding them here is safe;
/// they're kept in one file purely so the console step has a single
/// obvious destination.
///
/// Each value can also be overridden at build time without editing source:
///
/// ```
/// flutter build apk --dart-define=GOOGLE_SERVER_CLIENT_ID=...apps.googleusercontent.com
/// ```
///
/// See README's "Auth" section for how to obtain each one.
class GoogleAuthConfig {
  /// The **Web application** OAuth client ID.
  ///
  /// Counter-intuitive but required: `google_sign_in` sends this as
  /// `serverClientId` so that the ID token it returns carries a `aud`/`azp`
  /// pair Supabase's Google provider will accept. Using the Android client
  /// ID here instead is the single most common way this flow fails.
  static const serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '223206754657-3t89l07v4cjsrga7lmhckojhjqabi111.apps.googleusercontent.com',
  );

  /// The **iOS** OAuth client ID. Android needs no client ID at runtime —
  /// the native SDK identifies the app by package name + signing SHA-1
  /// registered in the console — so this stays empty on Android builds.
  static const iosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    defaultValue: '',
  );

  /// Whether sign-in can be attempted at all. False means the console step
  /// hasn't been done (or the build didn't pass the defines), and the UI
  /// says so plainly rather than letting the native SDK fail obscurely.
  static bool get isConfigured => serverClientId.isNotEmpty;
}
