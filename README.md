# Dosely

A minimalist Android medicine reminder app. Photograph the label, say the
dosage out loud, review what the AI understood, confirm — done. Reminders
fire from the device itself, so they work even with no network.

## How it works

1. **Scan** — camera photo of the label, read on-device with ML Kit OCR.
   The photo is discarded immediately; only the text ever leaves the camera
   screen.
2. **Speak** — say the dosage/schedule naturally ("one tablet twice a day,
   morning and night"), transcribed on-device.
3. **Understand** — the OCR text + transcript are sent to a Supabase Edge
   Function, which asks Claude to structure them into drug name, strength,
   dose, frequency, and times. This is the only step that touches the
   network, and no photo is ever included in that call.
4. **Review** — every field is shown in an editable form. Nothing is saved
   until you tap Save.
5. **Remind** — an exact alarm is scheduled directly on the device (source
   of truth for firing — no dependency on connectivity or a live app
   process), and the reminder is synced to Supabase for backup/multi-device.
   The notification itself has "Taken" / "Snooze 10m" actions.

## Project layout

```
dosely/
  app/                  Flutter Android app
    lib/
      core/             theme, ids, Supabase config
      data/local/       Drift (SQLite) — source of truth for scheduling
      data/remote/      Supabase sync + the parse-medicine client
      features/
        capture_ocr/    camera + on-device OCR
        voice_capture/  on-device speech-to-text
        review_edit/    AI-structured, user-editable confirmation screen
        notification_engine/  exact-alarm scheduling, action handling
        reminders_home/ the main list
        auth/           Google Sign-In
        settings/
  supabase/
    migrations/         schema (medicines, schedules, dose_logs) + RLS
    functions/parse-medicine/   edge function that calls Claude
```

Backend: Supabase project `dosely` (ref `twybepxnqayypzljhcnx`, org
`kgeamhakgmnfhsythhrx` — same org as your other project, separate project so
nothing shares data/schema with it).

## One-time setup

**1. Give the edge function a Claude API key.** It's stored as a Supabase
secret, never on-device — run this yourself so the key never lands in any
chat/session log:

```
cd ~/research/dosely
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...your-key...
```

Get a key at https://console.anthropic.com if you don't have one. Until
this is set, the review screen's "Try again" will fail — everything else
(capture, manual entry, notifications, sync) works without it.

**2. Install Flutter dependencies:**

```
cd ~/research/dosely/app
flutter pub get
```

**3. Register Google Sign-In.** Required — it's the only way into the app,
so nothing past the sign-in screen is reachable until it's done. It's a
browser-only job across the Google Cloud and Supabase consoles; the full
walkthrough is under [Auth](#auth) below.

## Running it

```
cd ~/research/dosely/app
flutter run                 # debug, attaches for hot reload
flutter build apk --release # ships a standalone APK
```

Needs an Android device or emulator (API 24+). On first run you'll be asked
for notification and exact-alarm permissions when you save your first
reminder, and for camera/microphone permission when you use those steps.

## Auth

**Google Sign-In is the only sign-in method.** The previous email
one-time-code flow, its custom Resend SMTP sender, its email templates, and
the `dosely://login-callback` deep link have all been removed.

The flow is native, not web-based: `AuthService.signInWithGoogle()`
(`app/lib/features/auth/auth_service.dart`) shows the on-device account
picker via `google_sign_in`, then exchanges the returned ID token for a
Supabase session with `GoTrueClient.signInWithIdToken`. No browser opens
and nothing redirects back into the app.

### Enabling it (one-time, manual)

> **Status: done for this project (2026-08-18).** The OAuth clients are
> registered in Google Cloud project `decent-digit-135023`, the Supabase
> Google provider is configured, and `serverClientId` in
> `app/lib/core/google_auth_config.dart` holds the Web client ID. Debug
> sign-in works end to end. The walkthrough below is kept for setting up a
> new environment, a release client (see [Before shipping a release
> build](#before-shipping-a-release-build)), or iOS.

The OAuth registration exists only in two web consoles — Google Cloud and
Supabase — and can't be done from this repo. Until it is done, the sign-in
button reports that the build isn't configured.

Budget about 15 minutes. Steps 1 and 2 are browser work (bar one `keytool`
command), steps 3 and 4 are local. Do them in order — step 2 and step 3
both consume IDs that step 1 issues.

Values you'll need throughout:

| Thing | Value |
|---|---|
| Android package name | `com.sagnikdas.dosely` |
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
("Dosely Android debug"). Save, and copy the **Android client ID** it
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

While you're in the dashboard, finish removing the old email sign-in from
the *server* side — the repo changes below don't do it on their own:

- **Authentication → Sign In / Providers → Email**: turn off.
- **Project Settings → Authentication → SMTP Settings**: clear the custom
  Resend sender if it's still there, and revoke that API key in Resend
  while you're at it.

> **You do not need `supabase config push`.** Doing the above by hand
> achieves the same result with no risk. The `[auth.external.google]` block
> in `supabase/config.toml` exists so the repo describes reality and so a
> local `supabase start` stack works; pushing it is optional and, if
> pushed *before* Google is verified working, it disables email sign-in
> server-side and can leave you unable to sign in at all. Confirm sign-in
> works first, then push if you want the config tracked. Should you push:
>
> ```
> export SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_ID="<web-id>,<android-id>"
> export SUPABASE_AUTH_EXTERNAL_GOOGLE_SECRET="<web-client-secret>"
> supabase config push
> ```

#### 3. Give the app the Web client ID

Already done for this project — `serverClientId` in
`app/lib/core/google_auth_config.dart` holds the Web client ID. Repeat this
only for a new project or a different Google client.

Two equivalent options. Permanent, and what you probably want:

```
# app/lib/core/google_auth_config.dart — put it in serverClientId's defaultValue
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
cd ~/research/dosely/app
flutter run
```

Tap **Continue with Google**. Success lands you on the reminders list; the
signed-in Google address then shows at the top of Settings.

### Before shipping a release build

A release APK is signed by a different key than debug, so Google won't
recognise it and sign-in fails on exactly the build you hand to other
people. Two extra pieces:

1. Generate a release keystore and an `app/android/key.properties` (neither
   exists in this repo yet — until they do, `flutter build apk --release`
   falls back to debug signing). Copy `app/android/key.properties.example`
   and follow "Release signing" in `app/README.md`.
2. Register a **second Android OAuth client** with that keystore's SHA-1,
   and append its client ID to Supabase's *Client IDs* list alongside the
   debug one. If you distribute through Play, use the SHA-1 from
   **Play Console → Release → Setup → App signing** instead, since Google
   re-signs your upload.

Also remember to **Publish app** on the consent screen (step 1a) — the test
user allow-list applies to release builds just as much as debug ones.

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
| "Sign-in isn't configured in this build" | `serverClientId` is still empty (step 3). |
| "Check your connection and try again" | Genuinely transient. Retry. |

None of the configuration cases resolve by retrying, and none of them mean
the account or the code is wrong.

## Reliability notes

- Notifications are the whole point of this app, so they've been tested
  directly: exact alarms fire on schedule with the screen locked, survive
  being re-armed on every app foreground (`HomeScreen`'s lifecycle
  observer), and the "Taken"/"Snooze" actions write to the local database
  correctly from outside the app's foreground UI.
- **OEM battery managers** (Xiaomi/MIUI, Samsung, Oppo/OnePlus, Huawei) are
  known to kill background alarms even with every permission correctly
  granted — this is a platform-level issue no app can fully solve. The
  mitigation here is that every schedule is re-armed each time the app is
  opened, so as long as it's opened occasionally, anything an OEM silently
  dropped self-heals. If you ship this, test on a couple of real
  aggressive-OEM devices and consider prompting users to allow-list the app.
- Local Drift SQLite is the source of truth for *when* things fire.
  Supabase is backup/sync only — reminders keep working with zero
  connectivity.

## Test data

Both the Supabase project and the local device used during development
have been cleaned of test rows — the home screen shows its empty state,
ready to go.
