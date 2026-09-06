# Medicyn iOS launch plan

**Plan date:** 4 September 2026

**Source revision:** `main` at `edc7c4f5c2f4b6cc83ac49f3ea80176b257be26e`

**Launch posture:** No App Store submission until the Phase 2 reminder-engine gate passes on a real device. iOS ships to the same bar Android already meets — reminders that fire correctly with no network and no live app process — not a lighter one.

## 1. Executive sequence

> **De-risk the encryption build → bootable local-only shell → reminder-engine correctness → identity → push and the care link → (in parallel: compliance and release automation) → beta → general availability**

This order puts the one unresolved technical risk first, and the code that actually protects a patient — the reminder engine — ahead of every feature that is optional in a way a missed dose is not. Compliance, store readiness, and CI are real work, but nothing in them can fail the way a silently dropped alarm can, so they run alongside the engineering phases rather than gating them.

Android's own principle carries over unchanged for iOS:

> **A private medication routine that works offline, with calm family backup when you want it.**

## 2. How priorities are determined

Work is ordered using four criteria, in this priority:

1. **Unknowns that could reshape the whole port come first.** The `sqlite3mc` iOS build is the one item that, if it fails, changes every downstream estimate — it is resolved before anything is scheduled against it.
2. **Patient safety before optional features.** iOS's 64-pending-notification ceiling is a hard platform limit, not a bug to patch later — the reminder engine has to be provably correct under it before the care-link, push, or any store-facing work builds on top of a system that might already be silently under-arming reminders.
3. **Dependency order.** Sign-in needs a bootable build; push needs a reminder engine it can trust to re-arm correctly; beta needs everything else done.
4. **Parallel tracks proceed on their own clock.** Compliance and release automation don't depend on notification-engine internals and shouldn't wait on them — but their exit criteria are not optional either.

## 3. Phase summary

| Phase | Sequencing | Primary objective | Exit decision |
|---|---|---|---|
| 0 | Sequential — start first | Confirm the encrypted database builds for iOS at all | Permit scheduling the rest of the port |
| 1 | Sequential | Bootable, local-only build on a real device | Permit reminder-engine work to begin |
| 2 | Sequential | Reminder engine correct under iOS's notification ceiling | Permit sign-in and push work to build on it |
| 3 | Sequential | Google and Apple sign-in both working | Permit push/care-link work |
| 4 | Sequential | Push and the caregiver care-link verified on-device | Permit closed beta |
| 5 | Parallel, from Phase 1 | App Store compliance and store assets ready | Permit submission |
| 6 | Parallel, from Phase 1 | CI compile checks and a signed release pipeline | Permit an installable beta build |
| 7 | Final — depends on 0–6 | TestFlight beta, then App Store release | Reach general availability |

## 4. Phase 0 — De-risk the encryption build

Medicyn's on-device database is encrypted via `sqlite3` built through Dart's native-assets hooks (`hooks.user_defines.sqlite3` in `app/pubspec.yaml`), pointed at `sqlite3mc` rather than upstream SQLite. That toolchain has only ever been exercised on Android in this repo.

**Current status:** Xcode 26.3 is installed with the iOS 26.2 SDK. Apple did not make an iOS 26.2 runtime available to this Xcode; the latest compatible iOS 26.3.1 runtime is installed and booted. The iOS 26 simulator build is currently blocked by the vendored Google ML Kit framework exposing an x86_64 simulator slice but no arm64 simulator slice; no iOS 26 simulator/device database acceptance claim is made. An x86_64 debug build did launch on the existing iOS 18.3 simulator as a lower-confidence smoke test.

- [x] Build the `sqlite3mc` native-assets hook for an iOS simulator target.
- [x] Build it for a real iOS device target (arm64) — simulator success does not guarantee device success.
- [ ] Confirm `PRAGMA key` against the resulting binary actually opens an encrypted file, not just that compilation succeeds.
- [x] No vendored CocoaPod fallback is needed: both native-assets targets assembled successfully; runtime encryption verification remains open.

**Acceptance:** A debug build opens the real encrypted database on both an iOS simulator and a physical device. No UI, auth, or push required yet.

The iOS 26 simulator acceptance run remains open until the ML Kit dependency is updated to an arm64-simulator-compatible release.

## 5. Phase 1 — Bootable shell, local-only

Goal: prove the plugin and CocoaPods graph resolves, and the existing UI runs on iOS, before adding any cloud dependency.

- [ ] Register the bundle identifier (`com.sagnikdas.medicyn`, mirroring the Android `applicationId`) in an Apple Developer account.
- [ ] Get a plain `flutter run` booting the Runner target on a simulator.
- [x] Resolve the current CocoaPods graph and confirm a clean `pod install`; the incremental/plugin-isolation history remains a process follow-up.
- [x] Add platform-adaptive iOS interaction chrome while preserving the Android Material path; see [`IOS-UI-ADAPTATION-2026-09-05.md`](IOS-UI-ADAPTATION-2026-09-05.md).
- [ ] Add `firebase_core`, `firebase_messaging`, and `google_sign_in` in their own commit, so a version conflict is attributable to a specific pod rather than the whole graph at once.
- [x] Add the `Info.plist` keys that don't depend on external registration yet: `NSSpeechRecognitionUsageDescription`, `NSFaceIDUsageDescription`.
- [ ] Confirm camera capture, on-device OCR, and speech-to-text (Apple's `SFSpeechRecognizer` via `speech_to_text`) each work on a real device.

**Acceptance:** Local-only mode works end to end on a physical iPhone — scan, speak, or type a medicine in, save it, and its local notification fires at the scheduled time with no account and no network.

The existing iOS 18.3 x86_64 simulator smoke-launched the Runner and rendered the Today screen. This does not close the iOS 26 acceptance item because the current ML Kit binary cannot be linked for an arm64 iOS 26 simulator.

## 6. Phase 2 — Reminder engine correctness

The load-bearing phase. Android arms reminders on `AlarmManager`, which has no practical cap. iOS's `UNUserNotificationCenter` caps a device at 64 pending local notifications, system-wide — request 65 is silently dropped, with no error and no callback. `NotificationService` now limits the `everyXHours` case to a 48-hour rolling window and allocates reminder slots across all active schedules, leaving headroom below that device budget.

- [x] Redesign `everyXHours` arming to a rolling window: arm only the next slice of occurrences (48 hours), and re-arm the next slice on app foreground — the same self-healing pattern `HomeScreen`'s lifecycle observer already uses for OEM-killed Android alarms.
- [x] Enforce a 60-slot reminder budget per patient, across every one of their schedules combined — leaving four iOS slots as headroom for snoozes/other app-owned notifications.
- [x] Confirm `daily` and `specificDays` need no scheduling change: both already pass `matchDateTimeComponents`, which maps to an efficient repeating `UNCalendarNotificationTrigger` on iOS — one slot per distinct time-of-day, not one per future occurrence.
- [x] Register a `DarwinNotificationCategory` with Taken/Snooze actions in `NotificationService.init()`, and set the matching `categoryIdentifier` in `_details()`.
- [x] Implement real iOS reads for `readPermissionState()` and `readDeviceHealth()` using the notification plugin's permission state and pending-request count.

**Acceptance:** A realistic 5–6 medicine regimen, including one `everyXHours` schedule, stays under 64 pending notifications with headroom, verified on a physical device. Taken and Snooze both work from a notification tap with the app force-quit.

## 7. Phase 3 — Identity: Google, then Apple

- [ ] Create the iOS Google OAuth client in Google Cloud Console (bundle ID, no SHA-1) — the README's Auth section already documents every step.
- [ ] Fill in the `GIDClientID` and reversed-client-ID `CFBundleURLTypes` block already commented into `app/ios/Runner/Info.plist`.
- [ ] Supply the real value via `GOOGLE_IOS_CLIENT_ID` (covers `google_auth_config.dart`'s `iosClientId`, which is already wired to read it).
- [ ] Register a Services ID and a Sign in with Apple key (`.p8`) in the Apple Developer console.
- [ ] Enable the Apple provider in Supabase Auth (same dashboard the Google provider was enabled in).
- [ ] Implement `AuthService.signInWithApple()` using Apple's native `AuthenticationServices` flow (the `sign_in_with_apple` package is the standard Flutter wrapper).
- [ ] Add the Sign in with Apple button to `sign_in_screen.dart`, styled per Apple's Human Interface Guidelines, alongside the existing Google button.
- [ ] Capture the name/email Apple returns on the *first* authorization only, into `CareService.upsertOwnProfile()` — Apple does not hand it back on later sign-ins.

**Acceptance:** Both sign-in paths land in a working Supabase session on a physical device. The existing local-only → signed-in database adoption path (`adoptLocalDatabaseIfNeeded`) is verified on iOS, not assumed from the Android test.

## 8. Phase 4 — Push and the care link

Sequenced after Phase 2 on purpose: shipping caregiver missed-dose alerts on top of a reminder engine that hasn't yet proven it won't silently drop alarms means the alerts themselves could be reporting the wrong thing.

- [ ] Register an iOS app in the same Firebase project as Android; download `GoogleService-Info.plist`.
- [ ] Generate an APNs authentication key (`.p8`) and upload it under Firebase's Cloud Messaging settings.
- [ ] Add a `Runner.entitlements` file (none exists today) with Push Notifications and Background Modes → Remote notifications enabled in Xcode.
- [ ] Confirm `notify-care`'s existing FCM HTTP v1 calls need no code change — FCM bridges to APNs on its own once the key above is in place.
- [ ] Test the silent `data_changed` re-arm push on a physical device with Low Power Mode on and Background App Refresh off, to characterize the latency gap against Android rather than assume parity with it.

**Acceptance:** The README's existing Phase 1–3 care-link manual checklists pass, repeated iOS↔Android and iOS↔iOS.

## 9. Phase 5 — Compliance and store readiness (parallel, from Phase 1)

- [ ] Complete the App Store Connect App Privacy questionnaire, derived from the existing `docs/compliance/pack/ROPA.md` and `docs/compliance/pack/SCOPE.md` rather than re-deriving the data inventory from scratch.
- [ ] Set `ITSAppUsesNonExemptEncryption` in `Info.plist` and complete Apple's export-compliance self-classification — the app encrypts its local medical database beyond transport security, so this needs a deliberate answer rather than the App Store Connect default prompt.
- [x] Write a TestFlight distribution doc, parallel to `docs/play-store/closed-testing.md`.
- [ ] Verify `account_deletion.dart`'s in-app deletion flow satisfies Apple's account-deletion requirement on iOS — the same code that already satisfies it on Android.
- [ ] Replace the placeholder `AppIcon.appiconset` with real branded icons.
- [ ] Produce an App Store screenshot set at Apple's required device sizes.
- [x] Make `app/pubspec.yaml`'s `description` and the README's app framing
  platform-neutral for iOS preparation; finalize store copy once both
  platforms are real.

Repository preparation for this workstream is tracked in
[`IOS-TESTFLIGHT-DISTRIBUTION.md`](IOS-TESTFLIGHT-DISTRIBUTION.md). It records
the current code evidence and the items that still require Apple Console
access, a legal export-compliance classification, or final design assets.

## 10. Phase 6 — CI and release automation (parallel, from Phase 1)

Matches the bar `.github/workflows/android-release.yml` already sets — it builds a signed AAB and uploads it as a workflow artifact, nothing more — rather than exceeding it.

- [x] Add a `macos-latest` job/workflow that builds an unsigned `.ipa` on every PR touching `app/`, as a compile-health check.
- [x] Add a manual-dispatch (`workflow_dispatch`) signed release workflow scaffold with protected signing/API-key secrets, a signed `.ipa` artifact, and optional TestFlight upload.
- [ ] Hold off on Fastlane unless plain `xcodebuild`/`altool` invocations become unwieldy — none exists in this repo today, and Android's own pipeline doesn't need one either.

## 11. Phase 7 — Beta, then general availability

Depends on every phase above.

- [ ] Upload the first signed build to TestFlight internal testing (mirrors Play's internal track).
- [ ] Run the full real-device QA pass, including Phase 2's alarm-budget check repeated against a real (not synthetic) multi-medicine regimen.
- [ ] Confirm Dynamic Type composes correctly with the app's own text-scale slider (`AppSettings.instance.textScale`, layered under `MediaQuery.textScaler` in `main.dart`).
- [ ] Open external TestFlight testing.
- [ ] Submit for App Store review; begin a phased release once approved.

**Acceptance:** The app is in front of the first real user outside the team.
