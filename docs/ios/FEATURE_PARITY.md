# iOS Feature Parity

**As of:** 10 September 2026, branch `feat/ios-implementation` off `main` @ `ad8b3af`.

This is a from-the-code audit, not a restatement of `MEDICYN.md`'s "iOS —
Scoped, none of it built" summary. That line is stale: real iOS work already
exists in the tree (an adaptive Cupertino/Material layer, iOS branches
throughout the notification engine, a CI compile-health workflow, a manual
signed-release workflow) and was verified in this pass, not assumed from
comments. Where this table says "Passed," it means one of: `flutter analyze`/
`flutter test` covers it, a local `flutter build ios` succeeded and the app
was actually run and screenshotted on an iOS Simulator, or the code path is
platform-generic with no Android-only branch. Where it says "Blocked" or
"Partially Passed," the reason is a specific missing credential, a specific
untested path, or a specific piece of native configuration — not a guess.

**What was actually run this session** (all from `app/`, unless noted):
`flutter pub get`, `flutter analyze` (clean), `flutter test` (552 tests,
all passing), `flutter build ios --debug --simulator`,
`flutter build ios --release --no-codesign` (the exact command
`ios-compile.yml` runs), `flutter run` against a booted iOS 18.3 Simulator
(app launched, Supabase initialized, onboarding screen rendered correctly —
screenshot taken), and `deno test` for the `notify-care` edge function (16
tests, all passing after this session's fix — see F4 below).

---

## How to read "Current iOS status"

- **Passed** — built, and either run/verified on-device or backed by
  platform-agnostic code plus tests.
- **Partially Passed** — the code path is shared/adaptive, but a specific
  behavior needs a physical device, real APNs delivery, or an Apple Developer
  account to actually confirm.
- **Blocked** — needs a credential, portal action, or Apple approval this
  session cannot obtain.
- **Not Applicable** — the feature does not exist in the app at all (checked
  against `lib/`, not assumed from docs).

---

## F1 — Photo-label + voice dosage AI confirmation

| | |
|---|---|
| **Android entry point** | Home → "Add medicine" sheet → Scan label / Speak details / Enter manually |
| **Files/classes** | `ocr_capture_screen.dart`, `voice_capture_screen.dart`, `review_edit_screen.dart`, `medicine_parser.dart`, `label_redactor.dart` |
| **Native APIs** | Camera (`camera` plugin), on-device OCR (`google_mlkit_text_recognition`), speech-to-text (`speech_to_text`) |
| **Persistent data** | `medicines`, `schedules` (Drift/SQLite, encrypted) |
| **Backend** | Supabase edge function `parse-medicine` (network-only; no platform branch) |
| **Notification/background** | None at capture time |
| **Current iOS status** | Passed (camera/OCR path) / Partially Passed (voice) |
| **Required iOS work** | None found — `ocr_capture_screen.dart` has zero `Platform.isAndroid` branches; it opens the in-app rear camera and runs ML Kit exactly as on Android. `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription` are already in `Info.plist` with real (non-placeholder) copy. |
| **Tests/acceptance** | `flutter test` covers `medicine_parser`/redaction logic (platform-agnostic). Camera/OCR/speech themselves are UI-plugin surfaces with no widget-test coverage on either platform — acceptance is manual, same as Android. |
| **Final status** | **Passed** for camera+OCR (device build succeeds; ML Kit links for arm64 device, confirmed by a successful `flutter build ios --release --no-codesign`). **Partially Passed** for speech: `speech_to_text` supports iOS's native Speech framework, but `SpeechListenOptions.onDevice` is left `false` on both platforms (documented in `MEDICYN.md`'s Known gaps — Apple's servers, not Google's, would see the audio on iOS instead), and no physical iPhone was available this session to confirm the mic prompt → transcript path end-to-end. |

## F2 — Pharmacy-agnostic tracking
No retailer dependency anywhere in `lib/` on either platform. **Not Applicable** as a porting concern — nothing to adapt.

## F3 — Offline-first reliability (on-device exact alarms)

| | |
|---|---|
| **Android entry point** | Every reminder save (`review_edit_screen.dart` → `NotificationService.scheduleForScheduleWithMedicine`) |
| **Files/classes** | `notification_service.dart` (1337 lines, extensively iOS-branched already), `notification_actions.dart`, `missed_doses.dart`, `interval_dose_sequence.dart` |
| **Native APIs** | Android: `AlarmManager` via `flutter_local_notifications`. iOS: `UNUserNotificationCenter` via the same plugin. |
| **Persistent data** | `schedules.updatedAt` (re-arm anchor), `dose_logs` |
| **Notification/background** | This *is* the background behavior — see below |
| **Current iOS status** | Passed (logic) / Blocked (device verification) |

**What's already built for iOS**, read directly from `notification_service.dart`:
- `DarwinInitializationSettings` with `requestCriticalPermission: true` and a
  registered `medicyn_reminder` notification category carrying `Taken`/
  `Snooze` actions (`DarwinNotificationCategory`/`DarwinNotificationAction`).
- A hard **60-slot pending-notification budget** (`_iosReminderSlotBudget`),
  because iOS silently drops local notifications past 64 pending — Android
  has no such cap. `_availableReminderSlots()` reads
  `pendingNotificationRequests()` and every arm path (`daily`,
  `specificDays`, `everyXHours`) degrades gracefully: fewer re-ring attempts
  per dose rather than failing to arm the dose at all.
- `everyXHours` schedules use a **48-hour rolling window** replenished on
  every `reconcile()` (foreground + `data_changed` push), not open-ended
  scheduling — the deliberate iOS-side answer to "no truly repeating
  every-N-hours primitive."
- `interruptionLevel: InterruptionLevel.timeSensitive` on the reminder
  category, so a reminder can still surface with Focus modes on.
- `readPermissionState()`/`readDeviceHealth()`/`requestNotificationPermission()`
  all have iOS branches distinct from Android's exact-alarm-permission gate
  (iOS reports `exactAlarmsAllowed: true` unconditionally — there is no
  iOS equivalent to ask about).

**Required iOS work still open:**
- `requestCriticalPermission: true` / `critical: true` asks for Apple's
  Critical Alerts entitlement (`com.apple.developer.usernotifications.critical-alerts`),
  which is **not currently in `Runner.entitlements`** and is only granted by
  Apple to a narrow set of app categories (medical-alert and safety apps,
  by manual review) — a consumer app is not guaranteed to receive it. This
  is silently harmless either way (iOS just denies the critical bit and
  treats it as a normal alert), but the request should not be read as
  "critical alerts are live" until Apple approves the entitlement.
- **No physical iPhone was available this session** to confirm: a reminder
  actually rings from a *terminated* app (not just backgrounded — this is
  the single most important behavior in the whole app, per the project's
  own bar: "iOS ships to the same bar Android already meets — reminders
  that fire with no network and no live app process"); DST/timezone-change
  re-arm; reboot survival (iOS reschedules local notifications automatically
  across reboot without an Android-style `BOOT_COMPLETED` receiver, but this
  is asserted from platform docs, not observed here).

| **Final status** | **Partially Passed.** The scheduling logic, budget management, and permission model are iOS-complete in code and covered by `flutter test`'s platform-agnostic scheduling tests (`notification_service` is not directly widget-tested, but its pure helpers — `nextWallClockDay`, `reminderLockScreenCopy`, `isPatientReminderNotification` — are). Device-verified ring-while-terminated is the one item genuinely **Blocked** on hardware access. |

## F4 — Family sharing + missed-dose alerts (push)

| | |
|---|---|
| **Android entry point** | Automatic — `HomeScreen._bootstrap` registers FCM token, `notify-care` edge function pushes on missed dose / data change / refill-low |
| **Files/classes** | `push_service.dart`, `push_handlers.dart`, `care_notifier.dart`, `supabase/functions/notify-care/{index,fcm}.ts` |
| **Native APIs** | `firebase_messaging`, APNs (via Firebase) |
| **Persistent data** | `device_tokens` (Supabase), install id in `SharedPreferences` |
| **Backend** | `notify-care` edge function, `register_device_token` RPC |
| **Notification/background** | Silent `data_changed` push re-arms alarms in a background isolate (`firebaseMessagingBackgroundHandler`); visible pushes (`missed_dose`, `refill_low`) draw a system notification |
| **Current iOS status** | **Fixed this session** — was Blocked, now Partially Passed |

**Two real, verified gaps found and fixed in this session, not merely documented:**

1. **No Push Notifications entitlement existed at all.** `ios/Runner` had no
   `.entitlements` file, so `FirebaseMessaging.instance.getToken()` would
   fail on a real device — caught and silently swallowed by
   `push_service.dart`'s `registerToken()` (by design, for the
   no-Firebase-configured case), which meant this would have failed *with no
   error surfaced anywhere*, indistinguishable from "Firebase isn't
   configured." **Fixed:** added `ios/Runner/Runner.entitlements` (`aps-environment`)
   and wired it into all three Runner build configurations via
   `CODE_SIGN_ENTITLEMENTS`; added `UIBackgroundModes: [remote-notification]`
   to `Info.plist` so a silent push can actually invoke the background
   handler. Verified: `flutter build ios --release --no-codesign` still
   succeeds; `xcodebuild -showBuildSettings` confirms
   `CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements` resolves.
2. **The FCM payload builder had no `apns` block at all** — confirmed by a
   comment in `fcm.ts` itself: *"No `apns` block: iOS is not started."* Per
   Apple's requirements, a push with no `alert`/`sound`/`badge` and no
   `content-available: 1` in `aps` is not a push APNs will wake a
   backgrounded/terminated app for — so every silent `data_changed` re-arm
   ping would have been **silently dropped on iOS**, and every visible
   missed-dose/refill alert would have arrived with no sound. **Fixed:**
   `buildFcmRequestBody()` now sets `aps.content-available: 1` +
   `apns-priority: 5` + `apns-push-type: background` for data-only messages,
   and `aps.sound: "default"` for messages carrying a `notification` block
   (FCM mirrors `notification` into `aps.alert` automatically, but not
   `aps.sound`). Covered by two new Deno tests in `fcm_test.ts`
   (16/16 passing).
3. **CI would have failed the archive step regardless of (1) and (2).**
   `Runner.entitlements` is checked in with `aps-environment=development`
   for local Xcode/Simulator runs, but `ios-release.yml` signs with
   `CODE_SIGN_STYLE=Manual` against a *distribution* provisioning profile,
   which only ever grants `production` — a mismatch there fails the archive
   with "doesn't support the Push Notifications capability." **Fixed:**
   added a step that reads the actual profile's own `aps-environment` via
   `PlistBuddy` and rewrites the entitlements file to match immediately
   before archiving, rather than hardcoding a value that would drift if the
   App ID's capability changes.

**Still required, and cannot be completed without operator/Apple action:**
- Enable **Push Notifications** capability for `com.sagnikdas.medicyn` in
  the Apple Developer portal (this is what actually populates
  `aps-environment` in the profile the new CI step reads — until then, the
  new step's own guard (`::error::` + `exit 1`) fails the release build with
  an explicit message rather than a cryptic codesign error).
- Register an **iOS Firebase app** for push delivery — a
  `GoogleService-Info.plist` already exists locally (git-ignored, present on
  this machine) naming `decent-digit-135023` / bundle id
  `com.sagnikdas.medicyn`, confirming the Firebase-side app registration is
  already done; what's outstanding is the Apple-side Push capability above,
  which Firebase also needs an APNs Auth Key or certificate uploaded for
  (Firebase Console → Project Settings → Cloud Messaging → Apple app
  configuration).
- Physical-device delivery test: foreground, background, and terminated —
  none possible from this sandboxed session (no iPhone attached, no APNs
  reachability).

| **Final status** | **Partially Passed.** Code-side (Flutter + edge function) is now complete and tested; delivery is Blocked on the Apple Push Notifications capability + APNs key upload, both operator actions. |

## F6 — Doctor-ready adherence export (GDPR JSON, PDF)

| | |
|---|---|
| **Android entry point** | Settings → "Share with my doctor"; Insights screen |
| **Files/classes** | `data_export_service.dart`, `adherence_export_service.dart`, `adherence_pdf.dart`, `adherence_report.dart`, `emergency_card_pdf.dart` |
| **Native APIs** | `pdf` (pure-Dart PDF generation, no native dependency), `share_plus` (native share sheet) |
| **Persistent data** | Reads-only; writes a temp file for sharing |
| **Current iOS status** | Passed |
| **Required iOS work** | None found. PDF generation is the pure-Dart `pdf` package (same renderer both platforms — the "em/en-dash vanishing under Helvetica" bug `MEDICYN.md` documents fixing was a font-metrics bug, not a platform one, and the fix is shared code). `share_plus` natively supports iOS's `UIActivityViewController`. |
| **Tests/acceptance** | Covered by existing PDF/export unit tests (platform-agnostic). |
| **Final status** | **Passed** — no platform-specific code exists in this path; risk is limited to the generic "has anyone run the iOS share sheet" gap common to every plugin here. |

## N3 — Emergency card
Same shape as F6: local-only table, `emergency_card_pdf.dart` is pure-Dart, `emergency_card_screen.dart` has no platform branches. **Passed.**

## F7 — Virtual caregiver dashboard

| | |
|---|---|
| **Android entry point** | Care tab (bottom nav) |
| **Files/classes** | `care_screen.dart`, `dose_feed_screen.dart`, `patient_reminders_screen.dart`, `phone_dial.dart`, `setup_health_panel.dart`, `change_history_screen.dart` |
| **Native APIs** | `url_launcher` (`tel:` scheme) for one-tap calling |
| **Current iOS status** | Passed |
| **Required iOS work** | None found — `phone_dial.dart` and the Care screens have no `Platform.isAndroid`/`isIOS` branches; `url_launcher_ios` is already resolved as a transitive dependency and handles `tel:` URLs on iOS identically. |
| **Final status** | **Passed** for UI/logic. Phone dial itself needs a physical device or a real Simulator-with-Phone-app-substitute to click-test (iOS Simulator has no dialer), same caveat that would apply to any tel: link. |

## F8 — Refill reminders (consumer tracking half)
`refill.dart` has no platform branches; reads `Medicines.tabletsRemaining` and computes a 5-day warning entirely client-side. **Passed.** (Reorder/referral action itself is **Not Applicable** — not built on either platform, per `MEDICYN.md`.)

## Onboarding, auth, consent

| | |
|---|---|
| **Android entry point** | App launch → `onboarding_screen.dart` → `sign_in_screen.dart` → `consent_screen.dart` |
| **Files/classes** | `auth_service.dart`, `google_auth_config.dart` |
| **Native APIs** | `google_sign_in` (native account picker on both platforms) |
| **Current iOS status** | Partially Passed |
| **What's built** | `auth_service.dart` already branches correctly: `GoogleSignIn.instance.initialize(serverClientId:, clientId: Platform.isIOS ? GoogleAuthConfig.iosClientId : null)`. `GoogleAuthConfig.iosClientId` is a `String.fromEnvironment` define, ready to receive `--dart-define=GOOGLE_IOS_CLIENT_ID=...` the day one exists. |
| **What's missing** | An **iOS OAuth client** does not yet exist in Google Cloud Console (confirmed: `GoogleService-Info.plist` has `ANDROID_CLIENT_ID` but no iOS `CLIENT_ID` key). `Info.plist` has the `GIDClientID` / `CFBundleURLTypes` block **pre-written as a comment**, ready to uncomment once that client exists — this is good existing work, not a gap in itself, but sign-in cannot function on iOS until the client is created. |
| **Final status** | **Blocked** on an operator action (Google Cloud Console → Credentials → new iOS OAuth client, bundle id `com.sagnikdas.medicyn`, no SHA-1 needed) — everything code-side is already in place and just needs the resulting client id plugged into `Info.plist` + a `--dart-define`. This is a **pre-existing, correctly documented blocker** (`README.md` § Auth → iOS already says this); nothing new found here. |

## Settings, profile, privacy, account deletion, logout
`settings_screen.dart`, `account_deletion.dart`, `privacy_policy.dart` — no platform branches found. Privacy policy/delete-account pages are already live at public URLs (`medicyn.doezly.com`) reachable identically from either platform's `url_launcher`. **Passed.**

## Subscriptions / premium / payments
No `in_app_purchase`, no StoreKit reference, no subscription code anywhere in `lib/` on either platform — confirmed by grep, not assumed. Matches `MEDICYN.md`'s locked decision ("When to charge: after evidence, not at launch"). **Not Applicable.**

## Deep links, sharing, analytics, crash reporting

| Item | Status |
|---|---|
| Deep links / URL schemes | **Not Applicable** — no `app_links`/`uni_links` usage in `lib/` (the `app_links` package present in `pubspec.lock` is a transitive dependency of another plugin, unused directly); Google Sign-In is native/ID-token, not browser-redirect, so it needs no scheme either (confirmed in `auth_service.dart`'s own doc comment). |
| Share (PDF/export) | **Passed** — `share_plus`, see F6. |
| Crash reporting (Crashlytics) | **Passed, with a real gap closed already by prior work (#115/#118):** `GoogleService-Info.plist` is registered with the Runner target, and an **"Upload Crashlytics dSYMs" Run Script build phase already exists** in `project.pbxproj` (`"${PODS_ROOT}/FirebaseCrashlytics/run"`) — confirmed by direct inspection, not assumed. |
| Analytics | **Not Applicable** — `IS_ANALYTICS_ENABLED: false` in the Firebase config; no analytics SDK in `pubspec.yaml` on either platform. |

## Adaptive iOS UI/UX (Phase 4 ask)

This is further along than `MEDICYN.md` suggests. Found in `lib/core/widgets/medicyn_platform.dart`, `medicyn_chrome.dart`, and used throughout `home_screen.dart`, `review_edit_screen.dart`:

- `isApplePlatform(context)` — reads `Theme.of(context).platform`, not
  `dart:io`, so widget tests can force either platform.
- `MedicynAdaptiveSwitch` — `CupertinoSwitch` vs. `Switch`.
- `MedicynAdaptiveBackButton` — chevron vs. arrow, tested.
- `showMedicynTimePicker` — `CupertinoDatePicker` wheel vs. Material dial.
- `MedicynBottomNav` — `CupertinoTabBar` vs. Material `NavigationBar`
  (tested in `platform_adaptive_test.dart`).
- `HomeScreen` has a genuinely separate iOS body: a `CustomScrollView` with
  a real month calendar (`DoseCalendar`), day selection, and a daily-progress
  ring — none of which the Android body (`AndroidTodayScreen`) has. This is
  not a reskin; it is a different information architecture per platform,
  which is exactly what the task's Phase 4 asks for ("not a generic
  Cupertino demo").
- Capture-method picker: `CupertinoActionSheet` on iOS vs. a Material
  bottom sheet on Android (`home_screen.dart`'s `_startCapture`).
- `showAdaptiveDialog` + `AlertDialog.adaptive` used for the Taken/Snooze
  prompt and the delete-medicine confirmation — Flutter's own
  platform-adaptive dialog, not a custom one.
- System typography (no bundled San Francisco — `pubspec.yaml` only bundles
  Public Sans, used identically on both platforms by design, not a gap).
- Confirmed running on-device (Simulator): the onboarding screen renders
  correctly at native resolution, correct safe-area handling, no clipping,
  themed consistently with the Bedside Chart palette.

**Not yet verified this session** (needs a physical device or more Simulator
time than this pass covered): Dynamic Type at large accessibility sizes,
VoiceOver labels/order, Reduce Motion, dark mode — `core/theme.dart` defines
both `MedicynTheme.light()`/`dark()` and is platform-generic, so there is no
reason to expect an iOS-specific failure, but "no reason to expect a failure"
is not the same claim as "verified."

---

## Toolchain / build health (new findings this session)

| Finding | Status |
|---|---|
| `flutter build ios --release --no-codesign` (the exact `ios-compile.yml` command) | **Passed locally.** Confirms PR #118's Pods-Runner build-ordering fix works — this was the memory-tracked open question. |
| `ios-compile.yml` / `ios-release.yml` CI runs | **Blocked on GitHub Actions billing** ("recent account payments have failed"), confirmed via `gh run view` — every recent run fails in 6-10s at runner allocation, before any build step runs. This is an account-level operator action, not a code issue. |
| Google ML Kit has no arm64 iOS-Simulator slice (Google's own upstream limitation, confirmed via web search — not fixed by a version bump) | The Podfile's existing `EXCLUDED_ARCHS[sdk=iphonesimulator*] = arm64` workaround (x86_64-only simulator build under Rosetta) is the correct, still-current mitigation. |
| **New finding:** that workaround no longer installs on this machine's **iOS 26.3** Simulator runtime — Apple's `installd` refuses the x86_64 binary outright ("This app needs to be updated"). It **does** install and run correctly on the same machine's **iOS 18.3** runtime (verified: app launched, Supabase initialized, UI rendered). | Recommend iOS 17/18-class Simulators for local development until Google ships an arm64-simulator ML Kit slice; the repo's own pre-existing "Medicyn iPhone 16 Pro iOS 26.3.1" custom Simulator (evidence of prior manual workaround attempts) is currently unusable for this reason and should be recreated against an 18.x runtime, or Simulator testing should target a device using iOS 18.x. Physical-device builds are unaffected (the exclusion only applies to the simulator SDK). |
