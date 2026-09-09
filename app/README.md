# medicyn

A new Flutter project.

## Release signing

The `release` build type in `android/app/build.gradle.kts` signs with a real
upload keystore from `android/key.properties`. If that file is missing, a
release build fails rather than shipping an APK signed with the shared
debug key. Debug and profile still use the debug keystore, so a fresh
checkout can `flutter run` / `flutter build apk --debug` with no signing
setup. `android/key.properties` and `*.keystore`/`*.jks` files are
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
keystore's. See "Before shipping a release build" under Auth, below.

## Auth

**Google Sign-In is the only sign-in method.** The previous email
one-time-code flow, its custom SMTP sender, its email templates, and the
`medicyn://login-callback` deep link have all been removed — from the repo
and from the hosted Supabase project alike.

The flow is native, not web-based: `AuthService.signInWithGoogle()`
(`lib/features/auth/auth_service.dart`) shows the on-device account picker
via `google_sign_in`, then exchanges the returned ID token for a Supabase
session with `GoTrueClient.signInWithIdToken`. No browser opens and nothing
redirects back into the app.

### Enabling it (one-time, manual)

> **Status as of 2026-08-18:** the OAuth clients were registered in Google
> Cloud project `decent-digit-135023`, the Supabase Google provider was
> configured, and `serverClientId` in `lib/core/google_auth_config.dart`
> held the Web client ID. Debug sign-in worked end to end at that point.
>
> **This needs re-checking.** The app's `applicationId` was renamed
> `com.sagnikdas.dosely` → `com.sagnikdas.medicyn` on 2026-09-03 (see "The
> renamed-package trap" below) — an Android OAuth client is registered
> against the package name **and** SHA-1 together, so the rename likely
> orphaned the debug client even though the debug keystore itself never
> changed. Confirm sign-in still works with a fresh `flutter run`; if not,
> the fix is step 1c below, repeated for the current package name.

The OAuth registration exists only in two web consoles — Google Cloud and
Supabase — and can't be done from this repo. Until it is done, the sign-in
button reports that the build isn't configured.

Budget about 15 minutes. Steps 1 and 2 are browser work (bar one `keytool`
command), steps 3 and 4 are local. Do them in order — step 2 and step 3
both consume IDs that step 1 issues.

Values you'll need throughout:

| Thing | Value |
|---|---|
| Android package name | `com.sagnikdas.medicyn` |
| Debug signing SHA-1 | see step 1b |
| Supabase project ref | `twybepxnqayypzljhcnx` |

#### 1. Google Cloud Console — register the app

**1a. Pick a project and configure the consent screen.** At
<https://console.cloud.google.com>, select an existing project or create
one, then go to **Google Auth Platform** (what used to be *APIs & Services
→ OAuth consent screen*, which now redirects there). Under **Branding**,
fill in app name, user support email, and developer contact email; under
**Audience**, set User type **External**. Nothing else on those forms
matters for this app — no scopes beyond the default profile/email, no
domain verification.

> **The test-user trap.** A freshly configured consent screen sits in
> publishing status **Testing**, and in that state *only* Google accounts
> listed under **Google Auth Platform → Audience → Test users** can sign in
> — everyone else is refused with "access blocked", which looks exactly
> like a broken app. Either add your own account there before testing, or
> press **Publish app** on the same page to open it to anyone. This limit
> is invisible from the app side; nothing in the error text points at it.
> If Audience already reads **In production**, there is no test-user list
> and nothing to do here.

**1b. Get the SHA-1 of the key that signs your build.** For debug builds
(`flutter run`, `flutter build apk --debug`) that's the shared Android
debug keystore:

```
keytool -list -v -keystore ~/.android/debug.keystore \
  -alias androiddebugkey -storepass android -keypass android
```

Copy the `SHA1:` line — the colon-separated hex, e.g.
`40:2D:37:...:76:6B`. Ignore SHA-256, it isn't used here.

**1c. Create the Android OAuth client.** **Credentials → Create
Credentials → OAuth client ID → Application type: Android.** Enter the
package name and the SHA-1 from above. Give it a name you'll recognise
("Medicyn Android debug"). Save, and copy the **Android client ID** it
issues — you'll need it in step 3, and Google won't prominently show it
again.

**1d. Create the Web OAuth client.** Same menu, **Application type: Web
application**. Leave both "Authorised JavaScript origins" and "Authorised
redirect URIs" completely empty — this client never handles a browser
redirect; it exists purely as the identity Supabase validates tokens
against. Copy both the **Web client ID** and the **Web client secret**.

> Yes, a phone app needs a *Web* client. The Android client is how Google
> recognises your specific build; the Web client is what makes Google issue
> an ID token that a backend is able to verify. Supabase is that backend.
> Using the Android client ID where the Web one is asked for (or vice
> versa) is the single most common way this setup fails.

You should now have three values: an Android client ID, a Web client ID,
and a Web client secret.

#### 2. Supabase Dashboard — enable the provider

Open
<https://supabase.com/dashboard/project/twybepxnqayypzljhcnx/auth/providers>
→ **Google** → **Enable Sign in with Google**, and fill in exactly this:

| Field | Value |
|---|---|
| Client IDs | the **Web** client ID *and* the **Android** client ID |
| Client Secret (for OAuth) | the **Web** client secret |

**Client IDs is a single comma-separated list**, not one ID — Web first,
Android second, no spaces:

```
<web-client-id>,<android-client-id>
```

(Older dashboards split this into a `Client ID` field plus a separate
`Authorized Client IDs` field. Same thing: the Web ID went in the first,
the Android ID in the second.)

Listing the Android ID is the part that gets skipped, and skipping it fails
every sign-in with an audience complaint. The reason: a token minted by the
native SDK on the phone is stamped with the *Android* client as its
audience, not the Web one, and Supabase rejects any audience it wasn't told
to expect. Append further IDs to the same list as you add release and iOS
clients later.

Leave **Skip nonce checks** and **Allow users without an email** off, and
ignore **Callback URL** — that belongs to the browser OAuth flow, which
this app never uses.

The old email sign-in is already off on the server side: the Email
provider is disabled and no custom SMTP sender is configured. Nothing to do
here — worth knowing only if you ever recreate the project, since the repo
changes don't achieve either on their own.

> **You do not need `supabase config push`.** Configuring the provider by
> hand in the dashboard, as above, achieves the same result with no risk.
> The `[auth.external.google]` block in `supabase/config.toml` exists so
> the repo describes reality and so a local `supabase start` stack works;
> pushing it is optional. Push only once Google sign-in is confirmed
> working — pushing beforehand also disables email sign-in server-side,
> which on a project that still depended on it would leave you unable to
> sign in at all. Should you push:
>
> ```
> export SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_ID="<web-id>,<android-id>"
> export SUPABASE_AUTH_EXTERNAL_GOOGLE_SECRET="<web-client-secret>"
> supabase config push
> ```

#### 3. Give the app the Web client ID

Already done for this project — `serverClientId` in
`lib/core/google_auth_config.dart` holds the Web client ID. Repeat this
only for a new project or a different Google client.

Two equivalent options. Permanent, and what you probably want:

```
# lib/core/google_auth_config.dart — put it in serverClientId's defaultValue
static const serverClientId = String.fromEnvironment(
  'GOOGLE_SERVER_CLIENT_ID',
  defaultValue: '123456789-abcdef.apps.googleusercontent.com',
);
```

Or per-build, leaving the source untouched:

```
flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=<web-client-id>
```

Committing the client ID is fine: OAuth client IDs are public by design and
ship inside every APK regardless. The client **secret** is the sensitive
half, and it belongs only in the Supabase dashboard from step 2 — it must
never appear in this repo or in the app.

#### 4. Test it

```
cd ~/research/medicyn/app
flutter run
```

Tap **Continue with Google**. Success lands you on the reminders list; the
signed-in Google address then shows at the top of Settings.

### Before shipping a release build

Google recognises an Android app by package name **plus signing
certificate**, and a release build is signed by a different key than debug.
So sign-in fails on exactly the build you hand to other people unless that
certificate is registered too. Nothing in the app changes for any of this —
`serverClientId` stays the Web client ID throughout.

**1. Generate an upload keystore and point the build at it** — see
"Release signing" above.

**2. Find the SHA-1 that ends up on users' devices.** Which certificate
that is depends on how you distribute.

*Direct APK.* It's your upload keystore's:

```
keytool -list -v -keystore ~/medicyn-upload-keystore.jks -alias upload
```

*Google Play.* It is **not** your keystore's. Play App Signing re-signs
your upload, so Google's own certificate is what reaches devices — and it
doesn't exist until you've uploaded something. Build a bundle (Play takes
an AAB, not an APK):

```
flutter build appbundle --release
```

Upload it to an Internal testing release, then open **Play Console →
Release → Setup → App signing**, which lists two certificates:

| Certificate | Signs | Register it so that |
|---|---|---|
| **App signing key** | what users install from Play | sign-in works for testers and real users |
| **Upload key** | what you build locally | sign-in works in a locally-built release APK |

Register both if you test locally-built release APKs alongside Play
installs.

**3. Register one Android OAuth client per SHA-1.** Google Cloud Console →
**Credentials → Create Credentials → OAuth client ID → Android**, package
name `com.sagnikdas.medicyn`, one client per certificate. A client holds
exactly one package + SHA-1 pair, so they can't be combined into one. Name
them so they're tellable apart — "Medicyn Android — Play app signing",
"Medicyn Android — upload key".

**4. Append each new client ID** to Supabase's *Client IDs* list (step 2
above), Web first:

```
<web>,<android-debug>,<android-play-app-signing>,<android-upload>
```

**5. Test from the Play internal-testing link**, not a sideloaded APK. Only
the Play install carries the app signing certificate, so it's the only
build that proves step 3 worked. Expect sign-in to fail in that first
internal-testing build: the SHA-1 can't be registered until Play has issued
it, which happens only after the upload.

If the consent screen is ever back in publishing status **Testing**, its
test-user allow-list applies to release builds exactly as it does to debug
ones (step 1a).

### iOS

Not set up. It needs its own **iOS** OAuth client (bundle ID, no SHA-1),
plus a `GIDClientID` key and a reversed-client-ID URL scheme in
`ios/Runner/Info.plist` — the exact keys and format are written out in a
comment in that file. The `GOOGLE_IOS_CLIENT_ID` define in
`google_auth_config.dart` covers `GIDClientID`, but the URL scheme has to
live in the plist. Android is unaffected by any of this.

### If sign-in fails

The sign-in screen reports the three real causes distinctly, so read the
message before changing anything — retrying is only ever useful for the
third:

| What you see | What it means |
|---|---|
| Nothing — the screen just returns | You dismissed the account picker. Not an error. |
| "access blocked" / "app not verified" from Google itself | Consent screen is in Testing and your account isn't a test user (step 1a). |
| A message naming the **audience** or "could not complete sign-in" | The Android client ID is missing from Supabase's Client IDs list (step 2). |
| A message naming the **signing certificate** | SHA-1 mismatch — wrong keystore registered, or a release build against a debug-only client (step 1c). |
| "not registered to use OAuth2.0" (visible with `adb logcat`, tag `Auth`) | The Android OAuth client's **package name** doesn't match, even if the SHA-1 is right — see the renamed-package trap below. |
| "Sign-in isn't configured in this build" | `serverClientId` is still empty (step 3). |
| "Check your connection and try again" | Genuinely transient. Retry. |

None of the configuration cases resolve by retrying, and none of them mean
the account or the code is wrong.

> **The renamed-package trap.** An Android OAuth client is registered
> against the **pair** package name + SHA-1, not the SHA-1 alone. Renaming
> the app's `applicationId` (as this project did, `com.sagnikdas.dosely` →
> `com.sagnikdas.medicyn`, September 2026) silently orphans it: the
> debug keystore never changed, so every symptom points at "SHA-1
> mismatch" while the SHA-1 is actually fine. The real Google-side error —
> "This android application is not registered to use OAuth2.0, please
> confirm the package name and SHA-1 certificate fingerprint" — only
> surfaces in `adb logcat` (tag `Auth`, from `com.google.android.gms`); the
> in-app failure just reads as the generic `[16] Account reauth failed`,
> identical to a transient network hiccup and a genuinely stale cached
> account (see [`auth_service.dart`](lib/features/auth/auth_service.dart)'s
> notes on `googleSignInCanceledIsStaleAccount`) — so this cause is easy to
> chase as "the account" or "the network" and never as "the package name."
> Fix: repeat step 1c (**Create Credentials → OAuth client ID → Android**)
> for the *new* package name with the *same* SHA-1, then append the newly
> issued client ID to Supabase's Client IDs list (step 2). Do this again
> for every release SHA-1 (upload key, Play App Signing) the next time a
> release build is cut — those clients are just as orphaned by a rename.

## Crash reporting (Firebase Crashlytics)

Crash reporting uses `firebase_crashlytics`, wired in
`lib/core/telemetry.dart` (`MedicynTelemetry.init`, called first thing in
`main()`). It rides the same gate as push: both need
`android/app/google-services.json` (Android) /
`ios/Runner/GoogleService-Info.plist` (iOS), both git-ignored and absent by
default. Without them, `Firebase.initializeApp()` throws, `MedicynTelemetry`
stays unavailable, and every crash-reporting call becomes a silent no-op —
the app behaves exactly as it would without Crashlytics at all, the same way
it already behaves without push.

Unlike Sentry's DSN, there is no separate secret to wire up: whatever build
has the config file(s) present has crash reporting live. CI does not
currently materialize either config file for release builds — see the
Firebase Console setup notes for what an operator needs to do before a real
release actually reports crashes.

On Android, the Crashlytics Gradle plugin (`app/android/settings.gradle.kts`,
`app/android/app/build.gradle.kts`) applies conditionally alongside
`google-services`, and uploads mapping/symbol info automatically on a
release build. On iOS, dSYM upload for symbolicated native crashes needs an
Xcode "Run Script" build phase — not something a config file alone
provides; see the Firebase Console steps for the exact script.
