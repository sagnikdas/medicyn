# Dosely product, UX, engineering, monetization, and launch audit

**Audit date:** 26 August 2026  
**Decision:** Ready for a controlled internal/closed beta after the critical items below are fixed; not ready for a public Google Play production launch in its current state.

## 1. Executive verdict

Dosely already has a credible product core. It is not merely a reminder prototype: it has encrypted per-user local databases, offline scheduling, dose history, refill counts, caregiver linking, optional cloud synchronization, explicit external-processing choices, privacy-preserving lock-screen copy, and a substantial automated test suite. The four-tab information architecture is understandable, and the visual system is calmer and more senior-friendly than many utility apps.

The largest risks are not cosmetic. They are:

1. **Processing consent is stored at device level, not account level.** A second Google user on the same phone can inherit the first user's cloud, AI, speech, and care-sharing choices.
2. **The Android permission strategy is likely to attract Play review scrutiny.** The manifest asks for both exact-alarm permissions, direct battery-optimization exemption, and full-screen intent, while the app requests the special accesses immediately on first Home load.
3. **The public account-deletion URL points at a private GitHub repository.** The source comments explicitly say private GitHub links return 404. That makes the off-app deletion route non-functional.
4. **Reminder arming failures and permission degradation are invisible to the user.** The app can save a schedule that is not actually armed and expose the failure only in debug output.
5. **A timezone lookup failure silently schedules in UTC for the rest of the process.**
6. **The first-medicine flow contradicts the product promise.** “Scan or speak” is presented as a choice, but Add always opens the scanner first; manual entry is not a first-class entry route.
7. **There is no production product analytics, active crash reporting, or real-device end-to-end test suite.** A reminder app cannot improve retention—or prove its core job works—without these feedback loops.
8. **Release signing is not configured on this checkout**, so a production AAB cannot yet be built and measured.

The recommended positioning is:

> **A private medication routine that works offline, with calm family backup when you want it.**

That is more defensible than “another pill alarm.” The largest incumbents already offer reminders, refills, reports, and family support at considerable scale. Dosely should compete on trustworthy privacy, simplicity, reliable Android delivery, and an unusually good parent–adult-child experience—not on the number of health features.

## 2. Audit basis and confidence

This report was based on the implementation, not the repository's planning Markdown. I inspected the Flutter application, Android manifest and Gradle setup, database and notification engine, onboarding and consent gates, capture flow, Today/Plan/Insights/Profile screens, care-link services, Supabase functions and migrations, privacy/export/deletion paths, dependencies, generated artifacts, and tracked files.

Verification completed:

- Flutter 3.41.3 / Dart 3.11.1.
- flutter analyze: **no issues**.
- flutter test: **436 tests passed**.
- Supabase edge functions: **68 tests passed** when run from their three function directories.
- The aggregate root-level Deno invocation fails because each function owns a separate import map. The functions themselves pass, but CI needs one documented root command.
- No integration_test or Android instrumentation suite was found.
- Release key properties are absent; the Gradle build correctly refuses to make an unsigned/debug-signed release.
- The current version is 0.1.0+1.
- The app targets the Flutter-provided Android API 36 and uses a minimum SDK of 24.
- Existing debug/profile APK sizes are not valid Play download-size measurements. The source assets are lean; measure the signed release AAB through Play Console before optimizing size.

This is a static/code-based product audit. It does not replace usability sessions with medicine takers, caregiver dyads, accessibility testing on real devices, a security penetration test, or legal review of health/privacy claims.

## 3. Scorecard

| Area | Current state | Launch assessment |
|---|---:|---|
| Core reminder value | 8/10 | Strong offline foundation; reliability state is not visible |
| Information architecture | 7/10 | Clear tabs; activation flow is unnecessarily serial |
| Senior/accessibility UX | 6/10 | Good sizing intent; system font scaling is overridden and some controls are undersized |
| Privacy/security | 7/10 | Encryption and disclosure are strong; account-scoped consent bug is serious |
| Caregiver value | 7/10 | Real differentiation; invitation, delivery visibility, and role model need work |
| Insights | 5/10 | Useful start; one headline is computed incorrectly and reports are missing |
| Engineering quality | 8/10 | Analyzer and tests are excellent; no device E2E/CI release gate |
| Observability/growth measurement | 2/10 | No product event system; Sentry dependency is disabled |
| Play policy readiness | 4/10 | Target API is good; permissions, public URLs, declarations, and signing block launch |
| Monetization readiness | 2/10 | No billing or entitlement system; product can support a trustworthy freemium model |

## 4. What should be preserved

Do not throw away the parts that already make Dosely credible:

- **Core works without an account or network.** This is both a product advantage and a trust advantage.
- **Medical data is encrypted locally**, with per-account files and secure key/session storage.
- **External processing is optional** and split into cloud backup, Anthropic parsing, Google speech, and care sharing rather than hidden behind one vague switch.
- **Medicine names are hidden on the lock screen by default.**
- **The user can export data and request account deletion in-app.**
- **Care links require confirmation** and carry actor attribution for edits.
- **Dose occurrence logic handles recurrence, time zones, DST, retention, snooze, and deterministic log identities** more carefully than most early products.
- **Reduced motion, narrow layouts, large text testing, and calm copy** show the right audience instincts.
- **The automated test base is unusually strong** for this stage.

The work now is to make those qualities visible, reliable, and easy to activate.

## 5. Critical findings: fix before public launch

### P0-1 — Consent choices leak across accounts on the same device

**Evidence:** app/lib/core/app_settings.dart:31-35 and 99-117 store all consent flags under global SharedPreferences keys. app/lib/core/app_settings.dart:182-210 writes them without a user identifier. Signing out does not reset or switch these flags, and sign-in immediately calls ConsentService.syncToServer.

**Impact:** Person B can sign into a phone after Person A and inherit Person A's decisions to send data to Supabase, Anthropic, Google speech, or a caregiver. Person B can also skip the consent screen because has_recorded_consents is device-global. This is both a privacy defect and a broken legal record.

**Primary fix:** Split settings into:

- **Device preferences:** theme, display scale, onboarding seen, lock-screen privacy.
- **Account processing preferences:** namespace every consent key by Supabase user ID; give local-only mode its own owner ID.

On account change, load that owner's consent record before enabling any related code path. A never-seen owner must see just-in-time consent or default to all processing off. If local data is adopted into the first account, ask whether to carry the local choices over; do not silently copy them.

**Alternative:** Clear every processing consent on sign-out and ask again on each sign-in. This is safer than the current state but worse UX than account-scoped storage.

**Acceptance tests:** A grants all choices, signs out, B signs in; B sees all choices off and no sync/token/AI call occurs before B grants them. Returning to A restores A's own choices.

### P0-2 — Exact-alarm/full-screen/battery permission strategy is high risk

**Evidence:** app/android/app/src/main/AndroidManifest.xml:6-13 declares SCHEDULE_EXACT_ALARM and USE_EXACT_ALARM together, REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, and USE_FULL_SCREEN_INTENT. app/lib/features/notification_engine/notification_service.dart:280-310 requests notification, exact-alarm, and battery exemption in one method. Lines 313-347 make every dose a maximum-importance, full-screen, insistent looping alarm.

**Impact:** Google Play restricts USE_EXACT_ALARM to narrow core use cases, and full-screen intent is subject to declaration/review and graceful-degradation requirements. A medication-management app should not assume it will be treated as a clock alarm app. Direct battery exemption also needs a defensible core-function argument. Even if approved, an insistent full-screen alarm for every dose can cause opt-outs, one-star reviews, and uninstalls.

**Primary fix:**

1. Remove USE_EXACT_ALARM unless Play explicitly confirms eligibility; use SCHEDULE_EXACT_ALARM with user-granted special access.
2. Request POST_NOTIFICATIONS only when the first reminder is saved, after a short explanation.
3. Ask for exact scheduling only after the user enables a reminder that needs it.
4. Do not immediately launch the battery-exemption system flow. First show a “Reminder reliability” screen with current state and OEM-specific guidance. Request direct exemption only if policy/legal review supports it.
5. Default to a high-priority heads-up notification with one sound. Offer **Gentle / Standard / Persistent** modes; persistent/full-screen must be an explicit opt-in.
6. If full-screen access is unavailable, degrade to heads-up notification and clearly show the state.

**Alternative:** Use inexact alarms as the no-special-access fallback and explain that Android may delay them. This is less reliable but better than pretending a reminder is exact.

**Relevant policy:** [restricted permissions](https://support.google.com/googleplay/android-developer/answer/9888170?hl=en), [full-screen intent requirements](https://support.google.com/googleplay/android-developer/answer/16965181?hl=en), and [Android exact alarm guidance](https://developer.android.com/develop/background-work/services/alarms).

### P0-3 — The off-app account-deletion route is not public

**Evidence:** app/lib/core/account_deletion.dart:3-6 links to a GitHub blob in sagnikdas/dosely. app/lib/core/privacy_policy.dart:4-7 explicitly states the repository is private and its GitHub blob URLs return 404. The privacy asset repeats the deletion link.

**Impact:** A user who uninstalls the app cannot use the required web route to request deletion. This is a direct Play submission blocker.

**Primary fix:** Publish permanent HTTPS pages on a public domain:

- /privacy — public, non-geofenced, non-PDF privacy policy.
- /delete-account — a functional form or clearly monitored email workflow, identity verification steps, data categories deleted/retained, and timing.
- /support — contact and expected response time.

Update the app, privacy asset, Data safety form, and Play Console to use the same URLs. Add an automated uptime/link check to CI or release operations.

**Alternative:** A public static GitHub Pages site is acceptable for beta if it is independent of private-repository access, but a branded domain is more durable.

Google's account deletion requirements are documented [here](https://support.google.com/googleplay/android-developer/answer/13327111?hl=en).

### P0-4 — A saved reminder can fail to arm without telling the user

**Evidence:** app/lib/features/notification_engine/notification_service.dart:743-785 returns a ReconcileReport, but its own comments at 775-780 and 846-851 say no caller consumes it. Home ignores the result at app/lib/features/reminders_home/home_screen.dart:160-161. The permission method's Boolean result is also ignored.

**Impact:** The most damaging failure mode is a confident UI and a missing dose alarm. Debug logging does not help a consumer.

**Primary fix:** Persist reminder delivery health per schedule:

- Notification permission: allowed/blocked.
- Exact alarm: allowed/blocked/not required.
- Last reconciliation: success/failure and timestamp.
- Next alarm expected at.
- Battery restriction status where observable.
- Push status for family alerts.

Show a non-dismissible Home card when any active schedule is unarmed: “2 reminders need setup” with one action. On a medicine row, show “Reminder active” or “Not active—fix.” Retry after returning from system settings and after reboot/app update.

**Alternative:** Prevent the save from completing until permission is granted. This is simpler but too coercive; saving the medication with a clearly degraded reminder state is better.

### P0-5 — Timezone lookup failure silently moves alarms to UTC

**Evidence:** app/lib/features/notification_engine/notification_service.dart:177-192 catches timezone lookup errors and uses UTC. The initialized flag then prevents retry for the life of the process.

**Impact:** In India, a 9:00 reminder could be scheduled 5.5 hours away from the intended time. This defeats the core product while appearing successful.

**Primary fix:** Do not schedule with UTC as a silent fallback. Keep initialization retryable; show a blocking reliability error with Retry; use the device's current UTC offset only as an explicitly degraded fixed-offset fallback and warn that daylight-saving changes require refresh. Record the failure in crash/diagnostic telemetry without medicine data.

**Acceptance tests:** Invalid timezone identifier, transient plugin error, DST change, manual timezone change, reboot, and process cold start.

### P0-6 — Privacy claims and actual collection are not fully aligned

**Evidence:** app/lib/features/reminders_home/home_screen.dart:139-143 registers an FCM token for every signed-in user. app/lib/features/auth/auth_service.dart also registers it immediately after sign-in. The privacy copy describes token storage in connection with family alerts. The policy says explicit consent is captured for on-device health processing, but the consent model contains cloud, Anthropic, speech, and care choices—not a recorded local health-data choice.

**Impact:** Data Safety answers and privacy wording can become inaccurate. Unnecessary token collection also contradicts the application's data-minimization positioning.

**Primary fix:** Register FCM only when a feature requiring remote alerts is enabled or a care link is being created. Update disclosure and Data Safety from the final behavior. Have privacy counsel choose the correct basis/copy for on-device health data; either record the claimed consent or stop claiming a consent record that does not exist.

**Alternative:** Keep universal signed-in push registration, but disclose it exactly and justify why it is necessary. This is less privacy-minimal.

### P0-7 — Production observability is effectively absent

**Evidence:** sentry_flutter is present, but app/lib/core/sentry_config.dart:4-11 sets an empty DSN and explicitly disables reporting. No analytics package or event layer was found.

**Impact:** You will not know whether reminders arm, onboarding converts, caregiver invites succeed, or a release crashes on a particular OEM. Play Vitals alone cannot explain product funnels.

**Primary fix:** Before external beta:

- Enable privacy-minimized crash reporting in release builds; strip medicine names, dosage, OCR text, transcripts, email, schedule IDs, and precise health timestamps.
- Add a small typed event layer with a written event dictionary.
- Record only non-health funnel metadata and buckets.
- Add a “Share diagnostics” action that exports permissions, app version, OEM, last arm result, and sync state without medical content.
- Use Play Console acquisition and Android Vitals alongside in-app events.

**Alternative:** If no third-party telemetry is acceptable, build aggregate counters in Supabase with rotating pseudonymous installation IDs and strict retention. Do not launch blind.

### P0-8 — Release pipeline and real-device proof are incomplete

**Evidence:** app/android/key.properties is missing; app/android/app/build.gradle.kts:77-107 correctly blocks release builds without it. No integration_test suite, device-farm configuration, or CI workflow was found. The current backend tests require three directory-specific invocations.

**Impact:** The signed release artifact has not been produced, sized, smoke-tested, or exercised against release OAuth credentials. Notification behavior is especially OEM- and build-signature-sensitive.

**Primary fix:** Establish:

- Play App Signing and a protected upload key.
- CI for formatting, analyzer, 436 Flutter tests, all 68 edge tests, migration/RLS tests, dependency audit, and signed AAB creation.
- A root test command that invokes each Deno folder with its import map.
- Real-device matrix: Pixel, Samsung, Motorola, Xiaomi/Redmi, Oppo/Realme if India is the first market; Android 7, 12, 13, 14, 15, and 16 where practical.
- End-to-end cases: install, local-only, first schedule, notification denial/approval, exact-alarm denial/approval, action buttons while killed, reboot, timezone change, snooze, sign-out/account switch, FCM care alert, offline edit/sync, upgrade/migration, deletion.
- Internal App Sharing and closed-track smoke tests of the exact AAB before every production rollout.

## 6. High-priority bugs and design gaps

### P1-1 — The Add flow does not offer the three methods it advertises

**Evidence:** app/lib/features/reminders_home/home_screen.dart:260-283 always opens OCR first, then optionally speech. The empty state at 749-767 promises “Scan a label or speak.” Manual entry is reached only indirectly after skipping/failing capture.

**Solution:** Make Add open a bottom sheet with **Scan label**, **Speak details**, and **Enter manually**. Ask for camera or microphone permission only after that choice. After scan, offer “Add spoken directions” as an optional enhancement rather than a mandatory second screen.

**Why it matters:** This is the highest-leverage activation change. It removes a camera startup and an irrelevant consent dependency for users who simply know the medicine name.

### P1-2 — Too many gates appear before first value

The current path is three marketing pages, consent, sign-in/local choice, then an automatic special-permission sequence, then medicine creation.

**Solution:** Use progressive disclosure:

1. One concise value/privacy screen.
2. Add the first medicine by the user's chosen method.
3. Explain and request notification/exact access at Save.
4. Ask for AI, speech, backup, and care consent only when the user selects those features.
5. Offer sign-in after the first local reminder succeeds or when backup/family is selected.

Do not hide material disclosures; move feature-specific choices to the moment they are understandable.

### P1-3 — Sign-in copy overpromises backup

**Evidence:** app/lib/features/auth/sign_in_screen.dart:65-66 says Google sign-in keeps reminders backed up on every device. Cloud-backup consent defaults off, so sign-in alone does not do that.

**Solution:** Say: “Sign in to enable cloud backup and family sharing. You choose what leaves this phone.” Then show Backup: On/Off and Last synced on Profile. Do not call the server copy end-to-end encrypted unless client-side encryption is actually added and independently tested.

### P1-4 — System accessibility font scaling is overridden

**Evidence:** app/lib/main.dart:104-107 replaces MediaQuery's text scaler with the app preference. The default 100% therefore ignores a user who set Android to larger text. AppSettings caps the app control at 150%.

**Solution:** Respect the system scaler and treat the in-app setting as an optional multiplier or preset. Test at Android's maximum supported scaling and at least 200%, with reflow rather than clipping. Keep a “Use device size” default.

Also increase the 32×32 avatar control in app/lib/core/widgets/dosely_chrome.dart and remove shrink-wrapped tap targets such as app/lib/features/settings/settings_screen.dart:297-300. Target at least 48dp interactive areas.

### P1-5 — “Most consistent” always means morning

**Evidence:** app/lib/features/insights/insights_screen.dart:97-103 computes only DayPart.morning, then lines 206-210 render it as the most-consistent period.

**Solution:** Compute rates for every day part with expected doses, choose the maximum with a minimum sample, represent ties honestly, and show a neutral state when no period has evidence. Add semantic labels to the weekly bars: “Wednesday, 2 of 3 doses, 67 percent.”

### P1-6 — Data export is incomplete and leaves a sensitive temp file

**Evidence:** app/lib/data/export/data_export_service.dart:158-169 omits tablets_remaining and tablets_per_dose. Lines 66-84 write health JSON to a temp file and do not remove it after sharing. The export label implies a complete access/portability copy.

**Solution:** Define a versioned export schema and test every persisted field. Include refill fields, consent-history records, profile/account metadata that is appropriate for access requests, remote care/change records, and an explicit list of intentionally excluded secrets. Delete the temp file in finally after the share operation, or let the user choose a destination and warn that the export is unencrypted.

### P1-7 — As-needed medicine can be configured but not usefully logged

**Evidence:** FrequencyType.asNeeded is accepted without times; the notification engine correctly schedules nothing, but Today generates no due occurrence and provides no prominent “Log as needed dose” action.

**Solution:** Add **Log dose now** to each PRN medicine, optionally capturing amount and a user-authored reason. Do not imply a schedule. Keep these events separate from adherence denominators.

### P1-8 — “Stop reminding” makes a medicine disappear

**Evidence:** the Plan tab watches only active schedules at app/lib/features/reminders_home/medicines_list_screen.dart:41. Stopped schedules retain history but have no visible archive/reactivation workflow.

**Solution:** Add Active / Paused / Completed sections, with pause-until, resume, end date, and archive. Preserve history. This also enables short antibiotic courses and medication holidays.

### P1-9 — Dose corrections cannot repair the metrics

The history screen preserves an immutable log and allows a contest note, which is good for auditability, but a mistaken Taken/Skipped action remains in adherence calculations.

**Solution:** Add a correction event: original action retained, corrected action and reason recorded, corrected_by and timestamp stored, calculations use the latest valid correction. Never mutate history invisibly.

### P1-10 — Raw exceptions and stalled loading states reach consumers

**Evidence:** app/lib/features/review_edit/review_edit_screen.dart:332-337 displays the raw exception. Auth errors include internal configuration/Supabase detail. app/lib/features/dose_confirm/dose_confirm_screen.dart:70-87 has no catch/finally, so a write failure can leave the screen spinning. Voice callbacks contain asynchronous setState calls without consistent mounted guards.

**Solution:** Create an error taxonomy with friendly action, stable support code, and private diagnostic cause. Put all busy-state code in try/catch/finally. Add mounted guards to plugin callbacks. Report technical causes to redacted telemetry.

### P1-11 — Loading and database errors look like empty data

**Evidence:** Home, Plan, and Insights commonly use snapshot.data ?? [] without representing loading or error. A failed stream can look like “No reminders yet” or zero adherence.

**Solution:** Show skeleton/loading, explicit retryable error, and true empty state separately. The empty state must only render after a successful empty query.

### P1-12 — Sync and family delivery are invisible

Cloud backup can fail silently; the user has no Last synced, pending-changes, or conflict state. A connected care link can be functionally degraded if cloud/push choices are off. Care alert history/delivery is not visible to the patient.

**Solution:** Add a small trust center:

- Backup On/Off, last successful sync, pending items, Retry.
- Family link Connected/Needs setup.
- Push reachable/unreachable and last health ping.
- Alert activity with sent/delivered/acknowledged where the platform provides it.
- Explain dependency changes before cloud or care is disabled.

### P1-13 — Push listeners survive sign-out

**Evidence:** PushService.unregisterToken removes the server token but does not cancel foreground, opened-app, or token-refresh subscriptions. The foreground callback retains the prior account's database until a later Home attaches new listeners.

**Solution:** Add detachForegroundListeners and cancel token refresh on sign-out/dispose. Make every callback verify the current owner before reading or writing. Test sign-out while a push arrives, account switch, and closed database behavior.

### P1-14 — Notification intensity and response model need user control

Current reminders are full-screen, maximum importance, looping, fixed ten-minute snooze, and auto-classified missed after one policy-defined window.

**Solution:** Offer reminder intensity, snooze choices (5/10/30/custom), Skip with optional reason, Taken earlier/custom time, quiet-hour rules, and a configurable response window. Use “unanswered” instead of making a clinical judgment that the dose was missed. Never let a smart feature silently change a prescribed schedule.

### P1-15 — Refill logic assumes whole tablets

The model accepts integer tablets remaining and integer tablets per dose. It cannot represent 0.5 tablets, millilitres, puffs, drops, injections, or explicit refill events.

**Solution:** Add quantity + unit, decimal consumption, refill transaction, threshold/date, pharmacy/contact (optional), and projected run-out. Keep the current simple two-field mode as the default and reveal advanced stock options progressively.

### P1-16 — Localization and time formatting are inconsistent

Strings are hard-coded in English, Material localization delegates are not configured, and history uses manual month/day/year and 12-hour formatting while other screens use 24-hour labels.

**Solution:** Externalize strings now, use locale-aware date/time formatting, and launch initially with one declared language if necessary. For an India-first rollout, prioritize English plus one language validated with the initial user cohort rather than machine-translating the entire app.

## 7. Engineering and performance gaps

These are not all launch blockers, but they will become expensive as usage grows.

| Finding | Evidence/impact | Recommendation |
|---|---|---|
| Foreign keys are off | app/lib/data/local/database.dart:456-463 explicitly says SQLite ignores declared cascades; manual cleanup can miss orphaned health notes | Add migration cleanup, enable PRAGMA foreign_keys=ON, and test delete/retention paths |
| Whole Home rebuilds every 15 seconds | app/lib/features/reminders_home/home_screen.dart:81-90; it also rebuilds calendar/derived data | Schedule the next meaningful state boundary, isolate the clock-dependent widget, memoize occurrence maps |
| All tabs mount eagerly | app/lib/features/shell/app_shell.dart:36-77 uses an IndexedStack; Insights can initiate work before first visit | Keep Home alive; lazily instantiate/cache the other tabs |
| Full-history streams feed day/week views | watchDoseLogs covers retained history and Insights recomputes a year-long streak in build | Query date ranges, calculate in repository/controller, cache by data revision |
| One snooze poll per reminder card | Each card can own a timer/query | Centralize current dose/snooze state in one stream/controller |
| Large UI/service files | notification_service, Home, Review, Care, and Insights carry many responsibilities | Split presentation, orchestration, platform adapter, and pure-domain logic; preserve the already good pure-function tests |
| Dependency upgrade backlog | pub reports 55 packages with newer incompatible versions; key majors include secure storage, local auth, and sharing | Schedule monthly controlled upgrades; prioritize security/platform packages and release-build tests |
| Backend test orchestration is fragmented | A root Deno test does not pick up per-function import maps | Add one script/Make target that enters each function directory; run it in CI |

## 8. Bloatware, dead code, and repository hygiene

There is **no evidence of conventional bloatware** such as ad SDKs, trackers, bundled media, duplicated fonts, or an obviously unnecessary framework. Most direct dependencies have a real production use. The meaningful opportunities are smaller and should not be exaggerated.

### Confirmed cleanup

| Item | Classification | Action |
|---|---|---|
| Tracked .idea files, especially .idea/caches/deviceStreaming.xml at about 119 KB | Repository-only bloat and developer-specific state | Remove from Git tracking while preserving local files; the root ignore already intends to ignore .idea |
| sentry_flutter with an empty DSN | Conditional dependency/code bloat; currently delivers no production value | Either configure privacy-safe release crash reporting before beta or remove it until ready |
| Stale generated/IDE comments in Gradle such as the application-ID TODO | Noise, not runtime bloat | Clean before handoff so real TODOs remain searchable |

### Dead-code or unfinished-code candidates

These should be verified with coverage/static call analysis before deletion:

- nextActionableDose in day_occurrences.dart appears to be used by tests but not the production UI.
- Several public database helpers—watchDoseLogsForSchedule, doseLogById, contestForDoseLog, doseLogsTouching, and the general schedulesWithMedicinesOnce path—appear production-unused or test-only. Mark test helpers accordingly, reduce visibility, or remove if no planned caller needs them.
- ReconcileReport is not dead; it is **unfinished product plumbing**. Use it to drive the reminder-health UI rather than deleting it.
- Care setup still polls on a timer even though push exists. Replace with Supabase Realtime, a push-driven refresh, or an explicit refresh if the live update justifies its complexity.
- The eager IndexedStack is not dead code, but it eagerly creates three screens that do not need to exist until selected.

### Do not “optimize” these away

- database.g.dart is generated Drift code. Its source size is not a reason to hand-edit or delete it.
- The Public Sans variable font is about 103 KB and is a reasonable single-font asset.
- The privacy asset is necessary for offline disclosure.
- Tests, migration comments, and the iOS runner are not Android Play bundle bloat. Keep iOS if a future iPhone launch is plausible.
- Firebase, Supabase, ML Kit, camera, local notifications, timezone, encryption, and secure storage all back current product behavior. Any removal should follow a feature decision, not an aesthetic dependency-count target.

The right size target is the **Play-delivered, ABI-split release download**, not the universal debug/profile APK. Build a signed AAB, upload it to Internal App Sharing, and use Play's size report before spending time on binary trimming.

## 9. Recommended UX redesign

### 9.1 First-session journey

**Current:** marketing carousel → four processing choices → Google/local choice → Home-triggered permission cascade → scanner → optional speech → edit form.

**Recommended:**

1. **Welcome:** “Private medicine reminders that work offline.” Two actions: Get started / Read privacy.
2. **Choose how to add:** Scan label / Speak details / Enter manually.
3. **Review medicine:** Always require the user to confirm name, amount, frequency, and times. AI suggestions are never authoritative.
4. **Enable this reminder:** Explain notification and exact-timing access in context, request one permission at a time, and show the fallback if declined.
5. **Success:** Show the next reminder and a “Send a test reminder” action.
6. **Optional expansion:** “Back up this plan” and “Add family backup” after the first schedule is known to work.

This moves time-to-first-value ahead of account creation and feature-specific consent while keeping the safety-critical confirmation.

### 9.2 Today

The Today screen should answer three questions in order:

1. **What needs action now?**
2. **What is next?**
3. **Is my reminder system healthy?**

Recommended changes:

- Keep one large attention card for due/unanswered doses.
- Add Taken, Snooze, and Skip without opening another screen for the common path.
- Show actual-time edit after Taken.
- Add a persistent but compact “Reminders active” indicator; expand only on trouble.
- Put calendar/history below today's actionable list.
- Do not rebuild the entire calendar every 15 seconds.
- Add “Log as-needed dose” as a distinct action.
- Use supportive copy. A miss is information, not failure.

### 9.3 Plan

Use stateful medicine management rather than an active-only list:

- Active
- Paused
- Completed
- As needed

Each medicine row should show the next dose, reminder health, stock projection, and last edit actor where family editing is active. Swipe actions can pause or refill; deletion remains behind confirmation.

### 9.4 Insights

Insights should help the user act, not merely score them:

- “Evening doses went unanswered twice” with a Change reminder action.
- Adherence by medicine and time window, only when the sample is meaningful.
- User-selectable 7/30/90-day ranges.
- Reason tags: forgot, away, asleep, side effect, ran out, chose not to take, other.
- A compassionate streak model; never hide useful history because a streak broke.
- PDF/CSV clinician report with date range, current medicines, scheduled vs responded doses, user corrections, and optional notes. Sharing must be explicit and processed locally where possible.

Avoid diagnosis, dosing advice, or causal medical claims.

### 9.5 Profile / trust center

Rename or structure Profile around:

- Account and backup status.
- Family sharing and alert delivery.
- Reminder reliability.
- Privacy choices and lock-screen visibility.
- Accessibility, theme, language.
- Export, delete, support, app version, and diagnostics.

The status should be legible without opening each setting: Backup On · Synced 3 min ago; Family connected · Alerts active; Reminder access · Needs attention.

## 10. Advanced feature roadmap

### Build next: high value, close to the current product

| Feature | Consumer value | Product/implementation note |
|---|---|---|
| Course start/end, pause, and taper phases | Supports antibiotics, temporary holds, and changing prescriptions | Model phases explicitly; every change is user-confirmed and auditable |
| PRN quick logging | Makes “as needed” real rather than a dormant schedule type | Exclude PRN from adherence denominators |
| Unit-aware refill workflow | Prevents running out; supports tablets, ml, puffs, drops, injections | Add explicit refill transactions and projected run-out |
| Reminder reliability center + test reminder | Directly builds trust in the core job | Use existing ReconcileReport and permission checks |
| Correction history | Fixes accidental actions without erasing audit history | Latest correction drives metrics |
| Shareable care invite | Turns family value into an acquisition loop | Signed expiring app link + OS Share + QR; retain code fallback and patient confirmation |
| Family alert activity | Builds trust that an alert was sent/acknowledged | Be honest where FCM cannot prove final human delivery |
| Doctor-ready report | High perceived value and a natural premium feature | PDF/CSV, locally generated, date-range and field selection |

### Build after retention is proven

| Feature | Why it may increase retention | Guardrail |
|---|---|---|
| Multiple caregivers and multiple patients | Fits real families and creates network effects | Role-based access, per-person consent, revocation, audit log |
| Escalation ladder | Alert caregiver A, then B if no acknowledgement | Quiet hours, rate limits, explicit patient control |
| Travel/time-zone assistant | Prevents silent schedule drift across zones | Ask whether to keep home time or local time; never infer prescription intent |
| Home-screen widget / Android quick action | Faster daily response | No medicine name on a locked launcher unless opted in |
| Suggested reminder improvements | “Evening responses are low; move prompt?” | Suggest only; never automatically alter a prescribed time |
| Symptom/side-effect journal | Creates a richer clinician conversation | User-entered observation only; no diagnosis or causality claim |
| Import from a simple CSV or competitor export | Reduces switching cost | Validate every field and require review before scheduling |
| Health Connect integration | Useful only if it eliminates duplicate entry or improves reports | Ask for the minimum data type/permission; do not add for a badge |

### Do not build yet

- **Drug interaction checking:** It is attractive in store listings, but unsafe to improvise. Launch only with a licensed, maintained clinical data source, clear regional coverage, versioning, monitoring, and legal/clinical review. A disclaimer does not repair incomplete interaction data.
- **Automatic dose changes from AI:** Never.
- **A broad health tracker:** Weight, mood, appointments, labs, and exercise would dilute the strongest wedge before Dosely has retention.
- **Wearable apps:** Wait for evidence that active users own and request a target platform.
- **Pharmacy refill commerce based on medicine data:** This creates privacy, consent, targeting, and partnership complexity. Validate the reminder product first.

## 11. Competitive reality and differentiation

The category is crowded. As of this audit, Google Play shows [Medisafe](https://play.google.com/store/apps/details?id=com.medisafe.android.client) and [MyTherapy](https://play.google.com/store/apps/details?id=eu.smartpatient.mytherapy) at more than five million installs each, with large review bases. They already market refills, reports, complex schedules, caregiver/family functions, and wider health tracking.

Therefore:

- “Medication reminder” is the search category, not a sufficient product position.
- Feature-count competition is unwinnable for an early launch.
- Dosely's most credible wedge is **offline/private core + calm senior UX + transparent family backup**.
- The two-person setup must be excellent. The adult child is often the discoverer/buyer; the parent is the daily user.
- Reliability should be demonstrated in the product and store listing: test reminder, setup health, no-account mode, private lock-screen default.

Suggested one-line listing proposition:

> Reliable medicine reminders that work offline, with optional family support and privacy you control.

Do not claim that Dosely prevents missed doses, improves medical outcomes, or is clinically validated unless that is substantiated.

## 12. Monetization strategy

### 12.1 Recommended model: trust-first freemium

The core safety utility should remain free. Do not charge users to receive a due reminder, mark it Taken/Skip, view their current medicines, export/delete their data, or use privacy controls. Paywalling the essential loop will damage trust and makes acquisition harder in a category with strong free alternatives.

| Tier | Proposed contents | Price hypothesis, not a final price |
|---|---|---|
| **Free** | Unlimited local medicines and reminders; manual entry; on-device label OCR; Taken/Snooze/Skip; PRN log; 30-day insights; basic refill alert; one-device local storage; export/delete/privacy | Free, no ads |
| **Dosely Plus** | Cloud backup/restore; 24-month analytics; advanced schedule phases; full refill projections; doctor PDF/CSV; custom reminder intensity/snooze; a modest monthly AI parsing allowance | India test: ₹99–149/month or ₹799–1,299/year. Global test: US$2.99–4.99/month or US$24.99–39.99/year |
| **Dosely Family** | Plus plus multiple caregivers/patients, escalation ladder, shared management, family dashboard, alert activity | India test: ₹199–299/month or ₹1,499–2,499/year. Global test: US$5.99–8.99/month or US$49.99–79.99/year |
| **Local Pro one-time** | Advanced local-only schedules, reports, and themes; no ongoing cloud/AI entitlement | Optional price test for subscription-resistant users; do not include cost-bearing cloud promises |

Run price discovery with beta users before locking these values. Annual should be the default value option, but monthly must remain clear. Avoid a trial that begins during onboarding; offer 7–14 days only after the user has created reminders and encounters a premium benefit.

### 12.2 AI usage

The server currently permits up to 40 parse requests in a 24-hour window. That is an abuse ceiling, not a viable consumer allowance. Track parse cost and success, keep manual entry and on-device OCR free, and include perhaps 5–10 successful AI-assisted additions per month in Plus initially. If demand is higher, revise based on cost rather than selling confusing token packs.

### 12.3 What not to monetize

- No behavioral advertising.
- No sale of medication, adherence, caregiver, OCR, transcript, or profile data.
- No medicine-targeted affiliate offers.
- No sponsored “recommendations” in the adherence flow.
- No paywall on export, deletion, privacy, or an already-created active reminder.

An ad SDK in a health reminder app would weaken the exact privacy positioning that can make Dosely distinctive.

### 12.4 Later revenue options

- **B2B2C sponsored access:** clinics, pharmacies, caregiver agencies, or employers pay for family seats. Only pursue after multi-tenant roles, contracts, audit logs, support, and regulatory/privacy review.
- **Care organization dashboard:** a separate product for consented adherence follow-up, not a hidden extension of consumer family sharing.
- **Research partnerships:** only opt-in, separately consented, de-identified where genuinely possible, and never required for app access.

These may have higher contract value but are a different company motion. Do not delay consumer validation to build them.

### 12.5 Billing implementation

Digital features and subscriptions in a Play-distributed app generally need [Google Play Billing](https://support.google.com/googleplay/android-developer/answer/9858738?hl=en). For the first Android-only release:

1. Use Flutter's official/community-supported Play Billing integration or a carefully evaluated entitlement service.
2. Send purchase tokens to a secure backend.
3. Verify and acknowledge purchases server-side.
4. Store entitlement state separately from health data.
5. Handle pending purchases, cancellation, grace period, account hold, restore, refund, and account switch.
6. Consume [Real-time developer notifications](https://developer.android.com/google/play/billing/backend) and re-query Google for authoritative state.
7. Make the app usable offline with a bounded entitlement cache.

Using a service such as RevenueCat can shorten subscription work and help a later iOS launch, but it adds another processor, SDK, privacy disclosure, and recurring cost. Direct Play Billing plus a small Supabase entitlement service is reasonable while Android is the only platform.

Subscriptions are currently listed at a 15% service fee in Google's [service-fee overview](https://support.google.com/googleplay/android-developer/answer/112622?hl=en-GB), subject to region/program changes. Model unit economics with the applicable Play fee, tax, AI calls, Supabase usage, crash/analytics tooling, and support.

### 12.6 Monetization gates

Do not turn on a public paywall until:

- D30 retention is credible for activated users.
- Reminder delivery health is observable.
- Backup/restore has been tested on a second physical device.
- Family alerts have delivery/status UX.
- Refund, restore, grace-period, and deletion cases pass.
- Premium benefits are visible without restricting the free safety loop.

## 13. Go-to-market plan

### 13.1 Initial customer

**Primary acquisition persona:** adult child, approximately 30–55, coordinating medication for a parent who lives independently or uses a separate phone.

**Primary daily user:** adult with multiple recurring medicines, often 50+, who values large controls, reliable alarms, and little setup.

**Secondary:** a self-managing adult with chronic medication who values privacy/offline use.

Start with one dyad and one job:

> “I want my parent's routine to stay private and simple, but I need to know when they may need help.”

### 13.2 Market sequence

1. **One-city / one-language cohort:** 20–30 medicine-taker/caregiver pairs recruited directly.
2. **India English closed beta:** 100–250 users across the OEM mix, with structured interviews.
3. **One additional validated language:** choose from observed demand, not assumption.
4. **Broader India production:** staged rollout only after reminder reliability and D30 gates.
5. **Global English:** localize pricing, date/time, privacy terms, support hours, and store screenshots first.

### 13.3 Acquisition channels

Prioritize channels with trust and intent:

- **Care invite loop:** shareable app link is the best native growth mechanism. Measure invite created → recipient install → claim → patient confirm → first acknowledged alert.
- **Caregiver communities:** senior-care, chronic-condition, and local resident groups; ask for feedback rather than spamming a download link.
- **Pharmacist/clinic pilots:** a simple QR handout after medication reconciliation. Never imply clinician endorsement without agreement.
- **Founder demonstrations:** short videos showing “set up a parent's first reminder in 60 seconds,” privacy choices, and a real test alert.
- **ASO:** medication reminder, medicine alarm, pill reminder, family medicine tracker, offline medicine reminder. Use natural language, not keyword stuffing.
- **Support-led word of mouth:** answer setup/reliability issues quickly; health utility reviews are heavily shaped by trust.

Do not spend materially on paid acquisition until activation and D7 retention are healthy. Then test a small Google App Campaign with separate caregiver and self-manager creative.

### 13.4 Store listing

Recommended screenshot story:

1. “Never wonder what is due now.”
2. “Works offline—no account required.”
3. “Add by scan, voice, or typing.”
4. “Private on the lock screen by default.”
5. “Family backup only when you choose.”
6. “Know when reminders need setup.”
7. “Share a clear report with your clinician.”

Use large real UI, one claim per image, high contrast, and localized device frames. The first video should show setup and a notification action—not a lifestyle montage.

Prompt for a Play review after several successful dose responses and no recent scheduling/sync error, never immediately after onboarding or an unanswered reminder.

### 13.5 Product-led loops

- Caregiver invite.
- Clinician report with a tasteful “Made with Dosely” footer and no public health data.
- Backup/restore moment on a new phone.
- Refill completion/share within a household.

Do not add cash referral rewards before fraud controls and retention are proven.

## 14. Measurement plan

### North-star metric

**Weekly protected doses:** scheduled dose occurrences for activated users where the reminder was armed and the user recorded a response.

This combines actual consumer value with delivery reliability. Raw “reminders created” can grow while the app fails its job.

### Funnel

Store view → install → Add started → first medicine saved → notification enabled → first reminder armed → first dose response → responses on 3 separate days → D7 → D30 → care invite created/accepted → trial → paid renewal.

### Launch-gate targets

Treat these as initial hypotheses:

- At least 65% of installers who open the app save one medicine.
- At least 75% grant notifications after the contextual prompt.
- At least 95% of saved active schedules show an armed next reminder or an explicit fix state.
- At least 60% of activated users record a first dose response.
- Activated-user D7 retention at least 35%; D30 at least 20%.
- Care-invite acceptance at least 40% among users who create an invite.
- Crash-free users at least 99.5% in closed beta.
- Zero known cross-account consent/data incidents.

Do not hide reliability failures from the denominator.

### Privacy-safe event dictionary

Useful events:

- onboarding_viewed / completed
- add_started with method
- add_completed with method, duration bucket, and number-of-times bucket
- permission_prompted / result by permission type
- reminder_arm_attempt / result with OEM/API and non-sensitive error code
- dose_response with action and lateness bucket
- sync_attempt / result with item-count bucket
- care_invite_created / claimed / confirmed
- alert_attempt / acknowledged
- report_exported
- paywall_viewed / trial_started / purchase_state

Never include medicine name, strength, dosage, free-text notes, OCR, transcript, phone number, email, care code, exact scheduled time, or raw database IDs. Use documented retention and honor analytics consent/legal requirements.

### First experiments

1. Add-method chooser versus current scanner-first route.
2. One-screen welcome versus three-page carousel.
3. Contextual permission explanation variants.
4. Test-reminder completion versus no test.
5. Care invite share link versus numeric-code-only.
6. Plus paywall after report preview versus after 30-day insight.
7. Supportive weekly insight versus streak-first framing.

Change one major variable per experiment and segment caregiver versus self-manager.

## 15. Google Play launch checklist

### Policy and listing

- [ ] Publish working public privacy, deletion, and support URLs.
- [ ] Complete the Health apps declaration as **Medication and Treatment Management**. Google lists medication reminders/adherence in that category: [Health apps declaration](https://support.google.com/googleplay/android-developer/answer/14738291?hl=en).
- [ ] Include a clear non-medical-device disclaimer and advice to consult a healthcare professional. See the [Health Content and Services policy](https://support.google.com/googleplay/android-developer/answer/16679511?hl=en).
- [ ] Make Data Safety match actual collection, sharing, encryption, deletion, retention, FCM, Google speech, Anthropic, Supabase, and telemetry behavior.
- [ ] Resolve exact-alarm, full-screen-intent, and battery-exemption declarations before submission.
- [ ] Complete content rating, target audience, ads declaration (“No ads” if the recommendation is followed), and app-access instructions.
- [ ] Give reviewers credentials and exact steps for backup/care functionality; local-only access is not enough to review restricted cloud features. See [app access requirements](https://support.google.com/googleplay/android-developer/answer/9859455?hl=en_EN).
- [ ] Avoid unsubstantiated medical outcome or clinical-validation claims.

### Artifact and platform

- [x] Target API 36 in the current Flutter toolchain. Google requires API 36 for new apps/updates from 31 August 2026: [target API requirements](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en).
- [ ] Create upload key, enroll in Play App Signing, protect recovery material, and build signed AAB.
- [ ] Register the release SHA fingerprints for Google sign-in/Firebase and test the release AAB.
- [ ] Confirm final application ID before the first Play upload; changing it later creates a new app.
- [ ] Run Play pre-launch reports and accessibility checks.
- [ ] Inspect Play-delivered size by device; do not use universal profile APK size as the goal.
- [ ] Add release notes, semantic version/build process, rollback decision, and support owner.
- [ ] Verify backups stay disabled for the encrypted medical database and that migration survives app upgrades.

### Testing and rollout

- [ ] If the developer account is a personal account created after 13 November 2023, satisfy the current closed-test rule of at least 12 opted-in testers for 14 continuous days before production access: [testing requirement](https://support.google.com/googleplay/android-developer/answer/14151465?hl=en-GB).
- [ ] Internal test with staff devices.
- [ ] Closed alpha with 20–30 dyads and observed setup.
- [ ] Closed beta with 100–250 users and the OEM matrix.
- [ ] Staged production at 5% → 20% → 50% → 100%, with a minimum observation window and explicit halt thresholds at each step.
- [ ] Monitor crashes, ANRs, reminder-arm failures, permission denial, care delivery, support contacts, and uninstall/review themes.

## 16. Twelve-week execution plan

### Weeks 1–2: eliminate launch blockers

- Account-scope every processing consent and add account-switch tests.
- Replace the private deletion/privacy URLs with public pages.
- Remove/rework restricted Android permissions; design contextual permission setup.
- Consume ReconcileReport and build reminder-health state.
- Replace silent UTC fallback.
- Detach push listeners on sign-out.
- Create release signing and CI skeleton.

**Exit:** no cross-account consent inheritance; every schedule is visibly armed or visibly degraded; signed internal AAB installs and authenticates.

### Weeks 3–4: improve activation and trust

- Build Add method chooser and direct manual flow.
- Reduce onboarding; move feature choices just in time.
- Fix sign-in claims, loading/error states, and raw errors.
- Honor system text scaling and 48dp touch targets.
- Add test reminder, sync status, diagnostics, and privacy-safe events.
- Fix Insights most-consistent calculation.

**Exit:** moderated tests show a new user can create and verify a reminder without assistance in under two minutes.

### Weeks 5–6: complete the medicine lifecycle

- Active/Paused/Completed states, start/end date.
- PRN quick log.
- Correction events.
- Unit-aware refill transaction and projection.
- Locale-aware date/time foundation.
- Complete and securely clean up exports.

**Exit:** temporary, paused, PRN, corrected, and refill cases have end-to-end tests.

### Weeks 7–8: strengthen family value

- Share link/QR plus code fallback.
- Explicit patient confirmation and revocation UX.
- Alert activity and degraded-state indicators.
- Test account switch, offline changes, FCM kill/reboot cases.
- Run 20–30 dyad alpha and weekly interviews.

**Exit:** at least 80% of observed dyads connect without developer help; no unexplained alert failures.

### Weeks 9–10: closed beta and store preparation

- Produce store assets and localized listing.
- Complete Data Safety, health declaration, app access, permission declarations, privacy/legal review.
- Run 100–250-user beta, support workflow, and price interviews.
- Fix beta reliability/activation issues before feature additions.

**Exit:** release gates in Section 14 are met or there is a documented decision not to launch.

### Weeks 11–12: staged launch

- Ship free core first if billing is not fully proven; do not let monetization delay a safe beta.
- If entitlements are ready, expose premium only to a small cohort.
- Roll out 5%, inspect for at least several days and a meaningful number of scheduled reminders, then 20/50/100%.
- Publish a transparent first release note and maintain fast support.

## 17. Prioritized backlog

### Must do before production

1. Account-scoped consents.
2. Public privacy/deletion endpoints.
3. Play-safe permission model.
4. Visible reminder health and non-UTC failure handling.
5. Signed release pipeline and release OAuth/Firebase test.
6. Crash/product observability with health-data redaction.
7. Real-device notification/reboot/account-switch E2E.
8. Data Safety/health declarations and accurate copy.

### Should do before broad acquisition

1. Add-method chooser and shorter onboarding.
2. System accessibility scaling and touch targets.
3. Sync/family delivery status.
4. As-needed logging, pause/completion, corrections.
5. Complete export and locale-aware dates.
6. Insights calculation/accessibility fixes.
7. Refill workflow.

### Can follow a successful launch

1. Multiple caregivers/patients and escalation.
2. PDF clinician reports and richer reason insights.
3. Travel assistant and widget.
4. Billing tiers and local Pro, if retention supports them.
5. Health Connect or interaction checking only with validated demand and appropriate safety infrastructure.

## 18. Final recommendation

Dosely should launch as a **trustworthy private reminder with optional family backup**, not as a medical intelligence platform. The codebase has enough depth for a serious beta, and its privacy/offline architecture is a real advantage. The immediate work is to remove contradictions:

- consent must belong to the person, not the phone;
- a saved reminder must be demonstrably armed;
- “scan or speak” must actually be a choice;
- backup and family status must be visible;
- privacy/deletion claims must work outside the app;
- Android permissions must match Play policy and user expectations.

Fix those, validate the two-person caregiver journey, and instrument the non-sensitive funnel. Only then layer subscription value around backup, reports, advanced schedules, refills, and family coordination. That sequence gives Dosely a realistic path to both trust and recurring revenue without weakening the free safety-critical core.
