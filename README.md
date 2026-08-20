# Dosely

A minimalist Android medicine reminder app. Photograph the label, say the
dosage out loud, review what the AI understood, confirm — done. Reminders
fire from the device itself, so they work even with no network.

## How it works

1. **Scan** — camera photo of the label, read on-device with ML Kit OCR.
   The photo is discarded immediately; only the text ever leaves the camera
   screen.
2. **Speak** — say the dosage/schedule naturally ("one tablet twice a day,
   morning and night"). On most Android phones the recogniser is Google's,
   and the audio may leave the device — see PRIVACY.md.
3. **Understand** — the OCR text + transcript are sent to a Supabase Edge
   Function, which asks Claude to structure them into drug name, strength,
   dose, frequency, and times. No photo is ever included in that call.
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
        voice_capture/  speech-to-text (Google on most phones; audio may leave)
        review_edit/    AI-structured, user-editable confirmation screen
        notification_engine/  exact-alarm scheduling, action handling
        reminders_home/ the main list
        auth/           Google Sign-In
        push/           FCM registration + inbound message handling
        care/           care links, and a linked person's dose feed
        settings/
  supabase/
    migrations/         schema (medicines, schedules, dose_logs) + RLS
    functions/parse-medicine/   edge function that calls Claude
    functions/notify-care/      edge function that sends FCM pushes
    tests/              adversarial SQL assertions against the RLS policies
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

**3. Register Google Sign-In.** Needed for cloud backup and family sharing.
You can still use the app without an account (local-only). Registering
Google Sign-In is a browser-only job across the Google Cloud and Supabase
consoles; the full walkthrough is under [Auth](#auth) below.

**4. Set up push.** Optional for a single user, required for a care link to
be worth anything — see [Push](#push). Without it the app builds, runs, and
fires local alarms exactly as before; only the alerts between two phones are
missing.

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
one-time-code flow, its custom SMTP sender, its email templates, and the
`dosely://login-callback` deep link have all been removed — from the repo
and from the hosted Supabase project alike.

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

Google recognises an Android app by package name **plus signing
certificate**, and a release build is signed by a different key than debug.
So sign-in fails on exactly the build you hand to other people unless that
certificate is registered too. Nothing in the app changes for any of this —
`serverClientId` stays the Web client ID throughout.

**1. Generate an upload keystore.** Run this in your own terminal (it
prompts for passwords) and keep the file outside the repo:

```
keytool -genkeypair -v \
  -keystore ~/dosely-upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload
```

Back it up somewhere durable. If you publish to Play and lose this key,
shipping an update needs a Google-assisted key reset.

**2. Point the build at it.** Copy `app/android/key.properties.example` to
`app/android/key.properties` and fill in `storeFile` (absolute path),
`storePassword`, `keyAlias`, `keyPassword`. That file and `*.jks`/
`*.keystore` are all git-ignored; none of them ever gets committed.

> Create `key.properties` only once the keystore actually exists.
> `android/app/build.gradle.kts` switches to release signing the moment the
> file is present, so a placeholder `storeFile` path fails the build rather
> than falling back to debug signing.

**3. Find the SHA-1 that ends up on users' devices.** Which certificate
that is depends on how you distribute.

*Direct APK.* It's your upload keystore's:

```
keytool -list -v -keystore ~/dosely-upload-keystore.jks -alias upload
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

**4. Register one Android OAuth client per SHA-1.** Google Cloud Console →
**Credentials → Create Credentials → OAuth client ID → Android**, package
name `com.sagnikdas.dosely`, one client per certificate. A client holds
exactly one package + SHA-1 pair, so they can't be combined into one. Name
them so they're tellable apart — "Dosely Android — Play app signing",
"Dosely Android — upload key".

**5. Append each new client ID** to Supabase's *Client IDs* list (step 2
above), Web first:

```
<web>,<android-debug>,<android-play-app-signing>,<android-upload>
```

**6. Test from the Play internal-testing link**, not a sideloaded APK. Only
the Play install carries the app signing certificate, so it's the only
build that proves step 4 worked. Expect sign-in to fail in that first
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
| "Sign-in isn't configured in this build" | `serverClientId` is still empty (step 3). |
| "Check your connection and try again" | Genuinely transient. Retry. |

None of the configuration cases resolve by retrying, and none of them mean
the account or the code is wrong.

## Push

Two notifications travel between a linked pair, and they are not variants of
one thing:

| Direction | What it is | Why it exists |
|---|---|---|
| Parent → caregiver | **Visible** alert: "Amma missed a dose" | The alert the care link is for. Arrives while someone can still act on it. |
| Caregiver → parent | **Silent** data message | Wakes the parent's app to pull and re-arm its alarms after the caregiver changed a schedule. |

The silent direction is the one that's easy to forget and expensive to omit:
without it, a schedule the caregiver changed doesn't reach the parent's alarms
until they next open the app — which could be a week — while the caregiver
believes the change is live.

Both go through the `notify-care` edge function. The **device** calls it
rather than a Postgres trigger firing on the insert: a trigger needs `pg_net`
(which Supabase keeps in the `extensions` schema that every security-definer
function here deliberately excludes from its `search_path`) plus a service key
stored in the database, and it would catch nothing extra — missed doses are
only ever produced by the parent's own device.

### Enabling push (one-time, manual)

Like Google Sign-In, this is mostly a browser job. Until it's done, the app
builds and runs with push disabled — `PushService` reports Firebase as
unconfigured and every local alarm keeps working.

**1. Create a Firebase project** at https://console.firebase.google.com. Use
the **same Google Cloud project** the OAuth clients live in ("Add Firebase to
an existing Google Cloud project"), so there's one project to reason about
rather than two.

**2. Register the Android app** in it with package name
`com.sagnikdas.dosely`, download `google-services.json`, and put it at:

```
app/android/app/google-services.json
```

That path is git-ignored on purpose. The file isn't secret — every installed
APK contains it — but it names one specific Firebase project, and a checkout
picking up someone else's would register its devices in the wrong one. The
Gradle build applies the `google-services` plugin only when the file is
present, so a fresh checkout without it still builds.

**3. Give the edge function a service account.** FCM's HTTP v1 API is
authorised by a service-account JWT, not an API key. In the Firebase console:
**Project settings → Service accounts → Generate new private key**. Then run
this yourself, so the key never lands in any chat or session log:

```
cd ~/research/dosely
supabase secrets set FCM_SERVICE_ACCOUNT="$(cat ~/Downloads/dosely-firebase-adminsdk-xxxxx.json)"
```

The function reads `project_id`, `client_email` and `private_key` out of it and
mints its own access tokens. `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`
are injected by the platform — don't set those.

**4. Apply the migration and deploy the function**, in that order (a function
that writes to a table the database doesn't have yet fails every call):

```
supabase db push
supabase functions deploy notify-care
```

**5. Reinstall the app.** A build made before `google-services.json` existed
has no Firebase configuration compiled into it, so `flutter run` again rather
than hot-reloading.

### Checking it works

Nothing about push is visible in the UI, which is exactly the problem with it.
Three things to look at, in order:

1. **`device_tokens`** should hold one row per phone that has signed in. Empty
   means registration is failing — no Play services, no
   `google-services.json` in the build, or no notification permission.
2. **`care_alerts`** records every push the server sent. `delivered_count = 0`
   is the interesting value: the alert was raised and reached nobody, which
   means the recipient's token is stale or their phone is unreachable.
3. **The function logs**, in the Supabase dashboard. `push_not_configured`
   means the service account is missing or malformed; `push_failed` lines
   carry FCM's own reason per token.

### Stale tokens

An FCM token dies when the app is uninstalled, its data is cleared, or FCM
simply reissues it. The function deletes a token when — and only when — FCM
says it's dead: a 404, or a 400 whose body names the token. Everything else
(429, 500, 503, a timeout) leaves the row alone, because deleting a working
token silences a family permanently while the app goes on looking healthy.
That classification is the one destructive decision in the push path, so it
has its own tests:

```
deno test --config supabase/functions/notify-care/deno.json \
  supabase/functions/notify-care/
```

### A token belongs to a phone, not an account

Sign out of one Google account on a phone and into another, and the FCM token
doesn't change. So `device_tokens` is keyed by the token itself, and
registering an existing one **moves** the row to whoever registered it — which
is what stops a handed-back phone from still receiving the previous person's
alerts.

Row-level security can't express that: the update arm of an upsert is checked
against the row being *replaced*, which belongs to whoever signed out, so the
registration would just fail. Hence `register_device_token`, a
security-definer function, and no insert/update policy on the table at all —
the same shape the care-link lifecycle uses. `supabase/tests/push_rls_test.sql`
asserts it, along with the rule that a device token is never readable by
anyone but its owner, not even by a confirmed caregiver.

### Phase 1 accident cases (still need a real phone)

The happy path was verified on two phones. These four were not. Automated
tests cover the mechanism; they cannot cover FCM, uninstall, or a second
physical device.

**Two devices, one account, one alert.** Sign the same Google account into
two phones. Let a reminder go missed. `care_alerts` must gain **one** row
for that dose, and the caregiver phone must ring once. The unique index on
`(link_id, dose_log_id)` is the lock; `notify-care` claims before send.

**Handed-back phone.** On the caregiver phone, sign out, then sign in as
the parent. Raise a missed dose for the original caregiver account. This
phone must stay silent. Sign-out deletes this install's token before the
session ends; a later registration moves the row only when the install id
matches.

**Uninstall prunes the token.** Uninstall the caregiver app. Raise a missed
dose. `notify-care` should delete the token when FCM answers 404 /
UNREGISTERED, not retry it forever. `delivered_count` may be 0 on that
send; the next send must not keep targeting the dead token.

**Cold-start tap.** Force-stop Dosely on the caregiver phone. Raise a
missed dose, tap the notification on the lock screen (unlock the *phone*
first if asked). Dosely may then ask for the device PIN — that cover is
deliberate and must stay; the feed opens after unlock, not on the lock
screen. The medicine name must not appear on the lock screen (care alerts
are `PRIVATE`).

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
- **Push is never in the firing path either.** A reminder is armed by the
  device's own exact alarms and fires whether or not FCM, Supabase, or the
  network exist. Push only carries news *between* two phones: a missed dose to
  the caregiver, and a schedule change back to the parent. Losing it degrades
  the care link; it cannot stop a reminder.

## Test data

Both the Supabase project and the local device used during development
have been cleaned of test rows — the home screen shows its empty state,
ready to go.
