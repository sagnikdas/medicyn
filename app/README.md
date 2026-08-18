# dosely

A new Flutter project.

## Release signing

The `release` build type in `android/app/build.gradle.kts` signs with a real
upload keystore when `android/key.properties` exists, and falls back to the
debug keystore when it doesn't — so a fresh checkout still builds
(`flutter build apk --debug`, `flutter run --release`, etc.) without any
signing setup. `android/key.properties` and `*.keystore`/`*.jks` files are
git-ignored; never commit them.

To set up real release signing:

1. Generate an upload keystore (adjust the alias/validity/output path as you
   like; keep the resulting `.jks` file **outside** version control):

   ```sh
   keytool -genkeypair -v \
     -keystore upload-keystore.jks \
     -keyalg RSA -keysize 2048 -validity 10000 \
     -alias upload
   ```

2. Copy `android/key.properties.example` to `android/key.properties` and
   fill in the real values:

   ```properties
   storeFile=/absolute/path/to/upload-keystore.jks
   storePassword=...
   keyAlias=upload
   keyPassword=...
   ```

3. Build a signed release as usual, e.g. `flutter build apk --release` or
   `flutter build appbundle --release`.

A release build also needs its signing certificate registered for Google
Sign-In, or sign-in fails on exactly the build you distribute — and under
Play App Signing the certificate that matters is Google's, not this
keystore's. See "Before shipping a release build" in the root `README.md`.

## Crash reporting (Sentry)

Crash reporting uses `sentry_flutter`, configured via
`lib/core/sentry_config.dart`. `SentryConfig.dsn` defaults to an empty
string, in which case `SentryFlutter.init` is a no-op (no crash capture, no
network calls) and the app behaves exactly as it would without Sentry. To
enable it, set a real DSN in `SentryConfig.dsn` (or wire it up via a
build-time define) before shipping a release build.
