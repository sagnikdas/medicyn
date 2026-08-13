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
        auth/           email magic-link sign-in
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

Ships with **email magic-link** sign-in (fully working, no setup beyond the
above) as the primary method. **Google Sign-In is implemented as a second,
faster option** — `AuthService.signInWithGoogle()` in
`lib/features/auth/auth_service.dart` drives the native `google_sign_in`
flow and exchanges the resulting ID token for a Supabase session via
`GoTrueClient.signInWithIdToken`, and `sign_in_screen.dart` shows a
"Continue with Google" button above the email field. It isn't usable yet,
though — no Google Cloud OAuth client has been registered for this app,
which is a manual one-time step in Google Cloud Console I can't do from
here. Until that's done, tapping the button fails fast and shows "Google
Sign-In isn't set up yet — please use email instead"; email + code is
unaffected and remains fully working. To enable Google Sign-In for real:

1. Google Cloud Console → your project → Credentials → Create OAuth client
   ID → Android, using `com.sagnikdas.dosely` and your signing key's SHA-1.
2. Create a second OAuth client ID → Web application (no redirect URIs
   needed) — this is the `serverClientId` `google_sign_in` needs.
3. Supabase Dashboard → Authentication → Providers → Google → paste that
   Web client's ID and secret, enable the provider.
4. Paste that Web client's ID into `_googleServerClientId` in
   `auth_service.dart` (currently left blank on purpose, which is what
   makes the button fail fast instead of hitting an unconfigured SDK).

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
