# Medicyn — Parallel Launch Plan (Android + iOS)

**As of:** 11 September 2026, `main` @ `b4e116a` (includes merged PR #119
"iOS implementation" and PR #120 "care-link cardinality").

**Goal:** ship Android and iOS in parallel this weekend. Everything under
"Not built" / "New — accepted, not started" / "Product gaps — after a
successful launch" in `docs/MEDICYN.md` is explicitly parked until both
platforms are live — do not pull any of that forward.

This doc was produced by cross-checking `docs/MEDICYN.md`,
`docs/ios/{FEATURE_PARITY,IMPLEMENTATION_PLAN,REAL_DEVICE_QA}.md`,
`compliance/COMPLIANCE.md`, `compliance/pack/*.md`, and
`docs/play-store/*.md` against the actual code on `main` — every item below
is evidence-based (file:line), not copied from the docs uncritically. Several
places where the docs and code had drifted are called out under
[Discrepancies found this session](#discrepancies-found-this-session).

## How to use this document

Each item is tagged by who/what does it:
- **[ENG]** — code change, doable by a subagent with repo access
- **[OPERATOR]** — a console/portal action (Play Console, Apple Developer,
  Firebase, GitHub billing) — not automatable, needs you
- **[BUSINESS/LEGAL]** — a decision or non-code deliverable (copy, legal
  judgment call)
- **[DOC]** — a doc-only fix

Items carry file:line evidence so a subagent can be pointed straight at the
relevant code without re-discovering it. **Track 0 first** — it's cheap and
several other items depend on its answers. Track A (Android) and Track B
(iOS) touch mostly disjoint files and can run in parallel. Track C
(compliance) is almost entirely non-engineering and can run alongside both.

---

## Status summary

| Track | State |
|---|---|
| **Android** | Furthest along. Build config, Play Data Safety answers, SCHEDULE_EXACT_ALARM declaration, and store listing copy are all *already written* — most of what's left is operator actions (keystore, Play Console, closed testing) plus one unverified regression risk (OAuth). |
| **iOS** | Real progress exists (adaptive UI, notification engine, push-notification bug fixed in PR #119) but nothing has run on physical hardware, and three operator-only blockers (Apple Developer account, GitHub Actions billing, a physical iPhone) gate most of the rest. One new code bug found this session (§0.2). |
| **Compliance** | Built for Android/Play only. Two DPAs unsigned, DPIA owed a re-read (was already true before iOS; now also iOS triggers it), and there is no App Store equivalent of the Play Data Safety form anywhere in the repo. |
| **Product gaps (pre-launch)** | Three tracked issues (#98, #99, #100) confirmed still genuinely open, plus two of three #96 sub-items; the third (#96c, missed-dose banner) is marked done in `MEDICYN.md` but its actual UI text could not be located in two passes — verify before trusting that checkbox. |

---

## Priority list

### Track 0 — Do first (cheap, high-signal, some items block others)

**0.1 [ENG] Verify the Android OAuth client survived the 2026-09-03 package rename.**
The app's `applicationId` changed `com.sagnikdas.dosely` → `com.sagnikdas.medicyn`, and a Google OAuth client is keyed on package name + SHA-1 together. No commit since the rename actually re-confirmed debug Google Sign-In works (`app/README.md:66-69,327-330` still documents this only as a risk to check).
_Action:_ `flutter run` a debug build, attempt Google Sign-In, confirm it succeeds or fails. If broken, this becomes Android item A3.

**0.2 [ENG] Fix `GoogleAuthConfig.isConfigured` — it ignores the iOS client ID.**
`google_auth_config.dart:40` only checks `serverClientId`, never `iosClientId`. Since `serverClientId` has a real default, `isConfigured` returns `true` on iOS even with no iOS OAuth client set — so `signInWithGoogle()` (`auth_service.dart:118`) skips its friendly "not configured" error and calls `_ensureGoogleInitialized()` with `clientId: null`, which will surface a raw, unfriendly native-SDK error on any iOS build before B4 (below) is done. Not mentioned in any of the three iOS docs.
_Action:_ make `isConfigured` check the platform-appropriate client id (`iosClientId` on iOS, `serverClientId` elsewhere).

**0.3 [DOC] Fix the stale Play Data Safety operator note.**
`compliance/pack/PLAY-DATA-SAFETY.md` still tells the reader the privacy policy is "deployed by `.github/workflows/pages.yml`" — that workflow was removed; the policy now lives at `medicyn.doezly.com` via the separate `doezly` repo (per `docs/MEDICYN.md`'s Android launch-blockers section).
_Action:_ update the paragraph to point at the real URL/deploy path.

---

### Track A — Android

**A1. [OPERATOR] Generate the release keystore + `app/android/key.properties`.**
Not present (correctly gitignored). Template exists: `app/android/key.properties.example`; steps documented in `app/README.md:8-31`.

**A2. [ENG] Confirm `flutter build appbundle --release` succeeds once A1 lands.**
Signing config is already fully wired (`app/android/app/build.gradle.kts:70-100` reads `keystoreProperties`; `:61` `applicationId` correctly `com.sagnikdas.medicyn`; `:66-67` versionCode/versionName from Flutter) — this should be a formality once the keystore exists.

**A3. [OPERATOR] Register an Android OAuth client for each SHA-1 Play shows** (app signing key and upload key), add both to Supabase Client IDs. Depends on 0.1's finding — only fully new work if 0.1 found it broken; otherwise this may just be adding the *upload*-key SHA-1 alongside an already-working one.

**A4. [OPERATOR] Play Console → Data Safety form.** Answers are complete and ready to paste from `docs/compliance/pack/PLAY-DATA-SAFETY.md` (once 0.3's fix lands).

**A5. [OPERATOR] Play Console → declare `SCHEDULE_EXACT_ALARM`.** Permission is present (`AndroidManifest.xml:7`); justification text is already written and duplicated into `docs/play-store/closed-testing.md` step 35.1.

**A6. [OPERATOR] Upload the signed app bundle to internal testing.**

**A7. [OPERATOR] Start closed testing** (Play's minimum tester count/duration). Full 62-step runbook already exists at `docs/play-store/closed-testing.md`, including finished, caregiver-voiced store listing copy (steps 19-22) — this is not unstarted writing work, it's an execution runbook waiting to be run.

**A8. [ENG/QA] Overlay-install verification on the Galaxy M33** (or an equivalent physical Android device). No evidence this has run — zero references anywhere in `docs/testing/`.

---

### Track B — iOS

**B1. [OPERATOR] Apple Developer Program enrollment + team ID.** Blocks every item below marked "needs B1."

**B2. [OPERATOR] Restore GitHub Actions billing on the repo.** Both `ios-compile.yml` and `ios-release.yml` currently fail in ~9 seconds at runner allocation, before any step runs — reconfirmed on PR #119. Settings → Billing & plans; not fixable via CLI.

**B3. [ENG/OPERATOR] Get access to a physical iPhone.** No device has been available in any session so far; blocks B9 entirely (a Simulator cannot substitute for the force-quit ring test, reboot persistence, or real APNs delivery).

**B4. [ENG, needs B1] Wire up the iOS Google OAuth client.**
Code side is ready: `Info.plist:32-49` has the exact commented `GIDClientID`/URL-scheme block, `auth_service.dart:107-109` already branches on `Platform.isIOS`. Just needs a real client id from Google Cloud Console (bundle id `com.sagnikdas.medicyn`, no SHA-1) passed as `--dart-define=GOOGLE_IOS_CLIENT_ID=...`. Do this together with 0.2.

**B5. [OPERATOR, needs B1] Apple Developer Portal: enable Push Notifications on the App ID, create a distribution cert + provisioning profile.** Base64-encode into the 5 secrets `ios-release.yml` already validates and expects: `IOS_CERTIFICATE_P12_BASE64`, `IOS_CERTIFICATE_PASSWORD`, `IOS_PROVISIONING_PROFILE_BASE64`, `IOS_PROVISIONING_PROFILE_NAME`, `IOS_TEAM_ID`.

**B6. [OPERATOR] Firebase Console → upload an APNs Authentication Key.** The iOS app is already registered in Firebase (`GoogleService-Info.plist` present locally, gitignored correctly) — this is the one remaining piece for push delivery.

**B7. [ENG/BUSINESS] Replace the AppIcon artwork.** Not merely "unbranded" — the current 1024×1024 in `Assets.xcassets/AppIcon.appiconset` is visually confirmed to be Flutter's stock default logo (files dated May/Mar 2025, predating this project).

**B8. [ENG] Fix `MedicynBrandMark`'s asset path.** Still does `Image.asset('android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png')` (`medicyn_chrome.dart`) — works today only because Flutter bundles it as a plain asset regardless of the path's platform-looking name; move it to a shared Flutter branding asset.

**B9. [ENG/QA, needs B3] Real-device validation pass.** Full script ready and entirely unchecked at `docs/ios/REAL_DEVICE_QA.md`: camera/OCR, speech, notification permission flows, airplane-mode/offline behavior, the core reliability claim (reminder rings foregrounded / backgrounded / **force-quit** / after reboot), lock-screen Taken/Snooze actions, timezone-change re-arm, the 60-slot pending-notification budget under load, Dynamic Type, dark mode, VoiceOver, small-phone and largest-iPhone layouts, iPad decision (currently universal — decide deliberately or restrict to iPhone-only).

**B10. [OPERATOR, needs B1] App Store Connect: create the app record, export-compliance classification, age rating, category, support URL** (already live at `medicyn.doezly.com/support`).

**B11. [BUSINESS] App Store screenshots + copy.** Android's listing copy is already written (`docs/play-store/closed-testing.md` steps 19-22) — this should mostly be a format/size adaptation, not fresh writing.

**B12. [OPERATOR, needs B10] App Store Connect API key for TestFlight upload** — `ASC_API_KEY_ID`, `ASC_ISSUER_ID`, `ASC_API_PRIVATE_KEY_BASE64`.

**B13. [ENG, needs B5/B12] TestFlight upload + internal testing.**

---

### Track C — Compliance (gates both Play and App Store submission)

**C1. [OPERATOR] Accept the Supabase DPA.** Google Cloud DPA (covers FCM + Crashlytics) is already accepted (`compliance/pack/DPA.md`, 2026-09-10); Supabase's is not.

**C2. [OPERATOR] Request/accept the Anthropic commercial DPA + zero-retention.** Not done.

**C3. [BUSINESS/LEGAL] Decide EU/UK data-region strategy.** `compliance/pack/TRANSFERS.md` explicitly instructs: do not market "GDPR-compliant transfers" until either the database migrates off `ap-southeast-1`, or all DPAs + a Transfer Impact Assessment are executed. Neither path is complete — this is a real decision, not a checkbox.

**C4. [OPERATOR] Appoint an Art. 27 EU representative, or restrict EEA countries at listing time.** Currently "not appointed" per `compliance/pack/SCOPE.md`.

**C5. [BUSINESS/LEGAL] Re-do the DPIA.** Two independent triggers now stack: the controller changed Sagnik Das → Doezly on 2026-09-08 (still not re-assessed — `compliance/pack/DPIA.md:259-260` says so explicitly), and shipping iOS adds a new data category (APNs tokens) that the current DPIA's processing description doesn't cover at all (it's scoped to "the Medicyn Android app"). One re-read can address both.

**C6. [DOC] Refresh the ROPA.** Stale since 2026-08-20, no mention of iOS/APNs anywhere. Do after C5 so it reflects the re-assessed state, not before.

**C7. [BUSINESS/LEGAL] Build an App Store Privacy Nutrition Label.** Doesn't exist anywhere in the repo — the entire compliance pack (`grep -rl "ios" compliance/`) has zero iOS hits. Play's Data Safety answers are the right source facts; this is a format translation, but it's net-new work, not adaptation of an existing draft the way B11's screenshots are.

**C8. [DOC] Same fix as 0.3** — listed here too since it lives in the compliance pack.

---

### Track D — Pre-launch product gaps

These are real, already-tracked gaps your own bar (`docs/MEDICYN.md` "Product gaps — before broad acquisition") called out as needed before broad acquisition — distinct from the parked "Not built" features.

**D1. [ENG] Family-delivery status** (issue #98) — no "did my edit reach the other phone" indicator exists anywhere in `app/lib/features/care/`. Confirmed absent, not stale.

**D2. [ENG] As-needed (PRN) manual logging** (issue #99) — `expected_doses.dart:86-87` still returns `const []` for `FrequencyType.asNeeded`; no manual "log now" action exists anywhere in the app.

**D3. [ENG] Locale-aware dates** (issue #100) — zero `DateFormat(` calls anywhere in `app/lib`; all date/weekday strings are hardcoded English arrays.

**D4. [ENG] Split `timingDefinedAt` from `updatedAt`** (issue #96a) — `missed_doses.dart:145` still calls `wasArmed(due, definedAt: schedule.updatedAt)` directly, so a cosmetic edit still resets missed-dose backfill.

**D5. [ENG] Hourly scheduled workflow for the `device_silent` alert path** (issue #96b) — the RPC/push path exists end-to-end (`push_events.dart`, `notify-care/index.ts`) but nothing calls it; no cron workflow exists under `.github/workflows/`.

**D6. [ENG] Verify — or build — the parent-facing missed-dose "supportive nudge" banner** (issue #96c, currently marked `[x]` done in `MEDICYN.md`). Two independent searches this session (a subagent's, and a follow-up grep across `home_screen.dart`, `dose_attention_panel.dart`, `care_notifier.dart`, `notification_service.dart`) found only a caregiver-facing care alert and an unrelated "reminder access" setup banner — not a parent-facing "your dose was logged missed" nudge. This checkbox may be stale. **Confirm before relying on it being shipped.**

---

### Parked until after both platforms launch

Do not start these this weekend — per your instruction, "Not built" features wait until both platforms are live:
- F5 (drug interaction warnings), F9 (family plan pricing), F10 (premium dashboard), F11 ("ask about my meds")
- N1 (refill basket), N2 (tests due), N4 (discharge summary translator)
- Post-launch gaps: multi-caregiver/multi-patient build-out, the F6 PDF-report doc inconsistency (`MEDICYN.md` line 41 says done, line ~287 says still open — resolve which is true when you get to F6/F7 work, not urgent now), travel assistant, home-screen widget, billing tiers, certificate pinning
- **The care-link cardinality build itself** (one caregiver → two parents, decided 2026-09-11 in PR #120) — the decision is locked in, but building it is F7/F9-shaped work, not a launch blocker. Leave it parked with the rest of F7/F9 unless you want it pulled forward.

---

## Discrepancies found this session

Worth fixing regardless of when the underlying work happens:
- `GoogleAuthConfig.isConfigured` doesn't check `iosClientId` (§0.2) — a real bug, not just a doc gap.
- iOS AppIcon is literally Flutter's stock logo, not merely "unbranded" — `docs/ios/IMPLEMENTATION_PLAN.md` §6.1 understates this.
- `compliance/pack/PLAY-DATA-SAFETY.md` still references the removed `pages.yml` deploy workflow (§0.3/C8).
- `docs/MEDICYN.md`'s Android checklist reads as if store listing copy is unstarted prose work; it's actually finished and sitting in `docs/play-store/closed-testing.md`.
- The #96c missed-dose banner may be stale (§D6) — flagged, not fixed, pending your confirmation.
