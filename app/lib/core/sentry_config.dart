/// Crash-reporting config for Sentry. Mirrors [SupabaseConfig]'s pattern of
/// a simple const holder for config that's safe to embed.
///
/// [dsn] defaults to an empty string, which is Sentry's documented way of
/// disabling the SDK: `SentryFlutter.init` sees the empty DSN, disables the
/// hub, and never makes a network call or reports errors — the app behaves
/// exactly as it would without Sentry at all. Set a real DSN here (or wire
/// one in via a build-time define) before shipping a release build that
/// should actually report crashes.
class SentryConfig {
  static const dsn = '';
}
