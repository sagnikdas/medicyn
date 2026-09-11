# Medicyn — Feature Checklist

**As of:** 8 September 2026, `main` @ `457b6a4`.

A medicine reminder for an elderly parent, and a way for one adult child in
another city to know it's working. The **parent** photographs a label, says
the dosage out loud, confirms what the AI understood, and taps Taken on a
notification. The **adult-child caregiver** installs it on both phones, links
them with an invite code, watches the dose feed, and is the one who would ever
pay.

How it works: Camera → on-device OCR → identifiers stripped → OCR text plus a
voice transcript sent to the `parse-medicine` edge function, which has Claude
fill a tool schema → editable review form → nothing saved until the user taps
Save. An exact alarm is scheduled on the device itself, Drift/SQLite is the
source of truth for *when*. Supabase is backup and sync only. The alarm fires
with no network and no live app process.

Visual design tokens (the "Bedside Chart" theme) live in `../DESIGN.md`,
paired with `.impeccable/design.json` and cited by name from
`android_today_screen.dart`, `day_dose_list.dart`, and
`.impeccable/surfaces/app.md` — kept at the repo root, machine-read.

---

## Core features

- [x] **F1 — Photo-label + voice dosage AI confirmation.** `capture_ocr`,
      `voice_capture`, `review_edit` + the `parse-medicine` edge function.
- [x] **F2 — Pharmacy-agnostic tracking.** No retailer dependency anywhere in
      the codebase.
- [x] **F3 — Offline-first reliability.** On-device exact alarms; DST-drift
      fix in #68.
- [x] **F4 — Family sharing + missed-dose alerts.** 1:1 only —
      `CareService.currentLink()` returns a single link.

### F6 — Doctor-ready adherence export
- [x] GDPR JSON export
- [x] Insights screen with weekly adherence
- [x] Per-schedule history
- [x] Formatted PDF — a 4-week clinician PDF (`adherence_report.dart` +
      `adherence_pdf.dart`), shared via "Share with my doctor" on Settings
      and Insights. Found half-built and uncommitted; fixed two real bugs
      (a static-method scoping error, and em/en-dashes silently vanishing
      under the PDF's Helvetica font) and added test coverage — see #106.

### F7 — Virtual caregiver dashboard
- [x] Dose feed
- [x] Patient-reminders view and editing
- [x] Phone dial
- [x] Device-health panel
- [x] Change history
- [ ] Caregiver-side trends
- [ ] Multi-person view — direction accepted (one caregiver, up to two parents), not started; needs the schema change described under "Care link cardinality" in Locked decisions
- [ ] Weekly digest

### F8 — Refill reminders → pharmacy referral
- [x] Consumer refill tracking (`refill.dart`, 5-day warning, #56/#69)
- [ ] Reorder or referral action

### Not built
- [ ] **F5 — Drug-drug interaction warnings.** Decision: Claude reasoning over
      the medicine list, not a licensed clinical database. Every flag ships
      with "AI-generated screening, not a clinical database — confirm with
      your pharmacist." Incremental trigger (new/changed medicine vs. active
      list only). Its own visible push, never folded into silent sync. Never
      names a drug in a notification payload.
- [ ] **F9 — Family plan pricing on care links.** Needs the multi-link schema
      now planned under "Care link cardinality" (one caregiver, up to two
      parents) — not built yet, but no longer blocked by the old 1:1 lock.
- [ ] **F10 — Premium caregiver dashboard.** Foundation only.
- [ ] **F11 — "Ask about my meds" assistant.** Same Claude pipe, new prompt.

### New — accepted, not started

Selected from a healthcare-gap review (September 2026). Scope rule: only
ideas that fall out of data Medicyn already holds, or point the existing
camera at different paper.

- [ ] **N1 — Refill basket.** Collapse per-medicine warnings into one list on
      one date a month. Plugs into `refill.dart`,
      `Medicines.tabletsRemaining`; no schema change needed. Not unit-aware —
      still a raw tablet count, so it won't sensibly cover ml, puffs, drops,
      or injections if one of those is ever added as a dose unit.
- [ ] **N2 — Tests that are due.** The monitoring a regimen implies
      (levothyroxine → TSH, warfarin → INR, metformin → HbA1c, statin →
      lipids + LFT). Plugs into `insights_screen.dart`, `TodayCareReminders`.
- [x] **N3 — Emergency card.** Medicines, doses, allergies, conditions, blood
      group, caregiver's number. Local-only (`EmergencyInfo` table) — unlike
      medicines/schedules this never needs to reach a caregiver's phone, so
      it deliberately does not sync. One tap from Profile
      (`emergency_card_screen.dart`), a printable PDF
      (`emergency_card_pdf.dart`), and included in the GDPR export
      (`data_export_service.dart`, schema v4) — see #107.
- [ ] **N4 — Discharge summary translator.** Photograph a discharge summary →
      plain language, every medicine created with times, red flags,
      follow-up date. Reuses the OCR → `parse-medicine` → review-and-confirm
      pipeline.

**Before N1/N2/N4 can start:**
- [ ] `Medicines.tabletsRemaining` is nullable/opt-in — N1's basket is empty
      for anyone who never counted tablets. Candidate: read quantity off the
      label at review time.
- [ ] Extend `redactPharmacyLabel()` for discharge documents (name, hospital,
      MRN, diagnosis, treating doctor) before any N4 work.
- [ ] N2's drug→test map should be a static table, not a Claude call.
- [ ] N2 must ask once for treatment start date and store it —
      `Medicines.createdAt` is when it was added to Medicyn, not when the
      doctor started it.
- [x] N3 must not be a lock-screen surface — one tap from Profile, plus a
      printable copy. Satisfied by construction: no notification touches it.
- [ ] N4 needs list-shaped extraction (current `sanitiseExtraction()` /
      `ParsedMedicine` assume one medicine), a multi-item review screen, and
      a re-weighted quota (`parse-medicine/quota.ts`).

Eight further ideas were reviewed as good fits but are not scheduled:
same-salt generic pricing, "how to take this" cards, batch-recall alerts, an
Ayush/allopathy interaction check, a records drawer, a misinformation check
against the person's own medicines, hospital-bill checking, and extending the
dose engine to non-pill daily tasks.

---

## Locked decisions

### Product and architecture
| Decision | Choice |
|---|---|
| Reminder firing | On-device exact alarms. Drift/SQLite is the source of truth for *when*. Cloud never arms or gates a reminder. |
| Auth | Google Sign-In only — native picker, ID-token exchange. No browser, no email/OTP. |
| Care link cardinality | **Changed 2026-09-11.** Target: one caregiver, up to two parents (e.g. both parents of the same caregiver). A parent still has exactly one caregiver. Not built yet — schema and app still enforce strict 1:1 both ways via `care_links_one_live_per_caregiver` (`supabase/migrations/20260818161500_care_links.sql:72-73`) and `CareService.currentLink()` (`app/lib/features/care/care_service.dart:417`), which returns a single link. Engineering work: relax the caregiver-side unique index to allow up to 2 live rows, and change `currentLink()` into a plural accessor plus a dashboard parent-switcher. |
| Dual roles | Nobody can be both a parent and a caregiver in different pairs. |
| Delete rights | The caregiver can add and edit, never delete. |
| Conflict resolution | Last-write-wins on a client-stamped `updated_at`, shown to both sides. |
| Local database | Encrypted per Google account (`medicyn-<userId>.sqlite`). |
| Platform | Android first (`com.sagnikdas.medicyn`, API 24+). iOS scoped, not shipped. |

### Money
| Decision | Choice |
|---|---|
| Who pays | The caregiver. Never the parent. |
| Free forever | Scan, speak, save, alarm. Offline. No account. |
| Paid | The care pair — missed-dose alerts, setup health, remote edit, call-from-alert. |
| Ads / data sale | Never. No ad SDK, no sale of health data, no sponsored pharmacy. |
| Clinics / payers | Not now — a B2B deal makes Medicyn a HIPAA Business Associate. |
| When to charge | After evidence, not at launch. |
| First paid plan | Annual, caregiver-paid, one pair. |
| Early users | Grandfathered free for at least a year after paid launches. |

### Regulatory posture
HIPAA does not currently apply — no covered-entity or business-associate
relationship, every field user-entered, no provider/EHR/billing integration.
GDPR/UK GDPR, the FTC Health Breach Notification Rule, Washington's My Health
My Data Act, CCPA/CPRA and Google Play's Health apps policy all bind the
product today. Full analysis: [`compliance/COMPLIANCE.md`](compliance/COMPLIANCE.md).

---

## Where it stands

### Shipped to `main`
- [x] Google SSO as the only sign-in
- [x] Sync that carries an edit, not just an insert
- [x] `care_links` + `profiles` + row-level security
- [x] Full link flow: invite, claim, confirm, disconnect
- [x] Adherence feed
- [x] Missed-dose detection on the device that owns the reminders
- [x] Push both directions (`device_tokens`, `care_alerts`, `notify-care`, FCM registration, inbound silent pull/re-arm)
- [x] Art. 13 privacy policy, consent, local-only mode, account deletion
- [x] OCR redaction, private care alerts, device-credential unlock
- [x] Caregiver editing with per-medicine change history, setup health on the Care screen
- [x] Refill tracking with 5-day warning
- [x] Bedside Chart visual pass (#91) and Android UX fixes (#94)

### Live infrastructure
- [x] **Supabase** (`twybepxnqayypzljhcnx`): migrations applied, edge functions deployed, Google provider configured with Web and Android client IDs, email sign-in and custom SMTP disabled
- [x] **Firebase** (`decent-digit-135023`): Android app registered, service account stored as `FCM_SERVICE_ACCOUNT` secret. An iOS app is registered too (`GoogleService-Info.plist`, bundle id `com.sagnikdas.medicyn`) — confirmed present locally (git-ignored, not committed); no APNs key is uploaded for it yet, so iOS push has no delivery path even though the app-side registration exists.

### Compliance
- [x] Phase 1 and 2 closed on `main`
- [x] Phase 3 paperwork landed (#48) — DPIA, ROPA, breach register, MHMD policy exist as documents
- [ ] DPAs, transfers, Art. 27 representative, Play Data Safety form — wait on operator action
- [x] Phase 4 technical items 4.3a–e closed

Full tracker: [`compliance/COMPLIANCE.md`](compliance/COMPLIANCE.md) → "Status
against `feature/phase-4`".

### Verification
- [x] Phase 0 device testing
- [x] Phase 1 happy path verified on two phones (2026-08-19)
- [ ] Four accident cases still need hardware

Device script: [`testing/REAL-DEVICE-VALIDATION-TEST-PLAN.md`](testing/REAL-DEVICE-VALIDATION-TEST-PLAN.md).

---

## Pending

### Android launch blockers
- [x] Fill the three placeholders in `compliance/PRIVACY.md` — already
      done: real effective date and contact email are in place, not
      placeholders
- [x] Host the policy at a public URL — moved off GitHub Pages (this repo
      is private; Pages on a private repo needs a paid plan, and every run
      of the old `.github/workflows/pages.yml`, now removed, failed as a
      result). Now served from the `sagnikdas/doezly` landing-site repo at
      `medicyn.doezly.com/privacy`, `/delete-account`, `/support`, and
      `/mhmd`. `app/lib/core/privacy_policy.dart` and
      `account_deletion.dart` point at the new URLs. All four verified
      live and returning the right content
      (`sagnikdas/doezly#2`, merged and deployed). One fix needed after
      merge: the first deploy used `fs.readFileSync` for the markdown,
      which 500'd on Cloudflare Workers (no filesystem at request time);
      fixed by inlining the content as string literals instead.
- [ ] Release keystore and `app/android/key.properties` (see `app/README.md`)
- [ ] Play Console Data safety form, matching `compliance/PRIVACY.md` (answers prepared in `compliance/pack/PLAY-DATA-SAFETY.md`)
- [ ] Complete the Play declaration for `SCHEDULE_EXACT_ALARM`
- [ ] `flutter build appbundle --release`, upload to internal testing
- [ ] Register an Android OAuth client for each SHA-1 Play shows (app
      signing key and upload key), add both to Supabase Client IDs — full
      walkthrough restored to `app/README.md` § Auth (was in the deleted
      root `README.md`, never migrated during the docs consolidation).
      **New risk found while restoring it:** the debug OAuth client was
      last confirmed working 2026-08-18, but the app's package name
      renamed `com.sagnikdas.dosely` → `com.sagnikdas.medicyn` on
      2026-09-03 — an Android OAuth client is keyed on package name *and*
      SHA-1 together, so the rename likely orphaned it even though the
      debug keystore itself never changed. Verify debug sign-in still
      works with a fresh `flutter run` before assuming it does.
- [ ] Closed testing for the required period
- [ ] Store listing written to the caregiver child, not the parent
- [ ] Overlay-install verification on the Galaxy M33

### Product gaps — before broad acquisition
- [x] System accessibility scaling — verified on-device (emulator, system
      font scale 1.3× + the in-app slider maxed at 150%) that
      `app/lib/main.dart` no longer overrides the OS text-size preference; it
      multiplies the device's own scale by the in-app one
      (`deviceScale * AppSettings.instance.textScale`). The doc's old claim
      was stale. Found instead: `ProfileMenuRow` (`app/lib/core/widgets/medicyn_chrome.dart`)
      hardcodes `maxLines: 3` on its subtitle, so at large combined scale
      real instructions get truncated with no way to see the rest (e.g.
      "Check reminder access" on Settings loses "...then send a test
      reminder" down to "...then send a..."). Fix tracked in
      [issue #96](https://github.com/sagnikdas/medicyn/issues/96).
- [x] Add-method chooser and shorter onboarding ("scan or speak" as a real
      choice) — verified in code and on-device: `onboarding_screen.dart` is a
      single-page value/privacy screen, and the Add flow already offers Scan
      label / Speak details / Enter manually as three co-equal options (built
      in `fdb96c0`, the same day as the audit that raised this). The doc's
      "not a first-class entry route" complaint no longer applies.
- [x] Device↔cloud sync status — already shipped: `SyncStatusStore` /
      `_BackupStatusCard` on Settings covers syncing, error, pending-count,
      and last-success states.
- [ ] Family-delivery status (did an edit reach the other side's phone) —
      split out as its own item, not shipped. Tracked in
      [issue #98](https://github.com/sagnikdas/medicyn/issues/98).
- [x] Pause/completion — shipped: `pauseSchedule`/`resumeSchedule`/`completeSchedule`
      wired to UI in `review_edit_screen.dart`, with status shown on the
      reminder card.
- [x] Corrections — shipped: the `DoseLogContest` note feature in
      `dose_history_screen.dart` lets a user dispute/correct a logged dose,
      reachable from the home screen and review/edit screen.
- [ ] As-needed (PRN) logging — no manual "log now" action exists for
      `FrequencyType.asNeeded` medicines, since `expected_doses.dart`
      deliberately yields no occurrences for them. Tracked in
      [issue #99](https://github.com/sagnikdas/medicyn/issues/99).
- [x] Complete export — verified: `data_export_service.dart` covers
      medicines, schedules, dose logs, contest notes, today-care-reminders
      and consents locally, plus profile, care_links, care_alerts and
      medicine_edits from Supabase, with a `remote_gaps` field if a remote
      fetch fails. Matches what `compliance/COMPLIANCE.md` §2.4 asked for.
- [ ] Locale-aware dates — no `DateFormat(` usage anywhere in the app;
      weekday/month names and relative-time strings are hardcoded English
      arrays. Tracked in [issue #100](https://github.com/sagnikdas/medicyn/issues/100).
- [x] Insights calculation and accessibility fixes — verified: the named
      bug ("most-consistent" period was hardcoded to `DayPart.morning`) is
      fixed; `insights_screen.dart` now computes rates for all `DayPart`
      values and picks the real max. No distinct Insights-specific
      accessibility issue found beyond the general text-scale work already
      tracked in issue #96.

### Product gaps — after a successful launch
Reviewed on 2026-09-08. The first five are confirmed accurate — genuinely
not built, nothing stale to correct.
- [ ] Multiple caregivers / multiple patients, and escalation — one caregiver
      to two parents is now the accepted direction (see Locked decisions); a
      parent still has exactly one caregiver, and escalation is unscoped
- [ ] PDF clinician report (F6's missing half)
- [ ] Travel assistant; home-screen widget
- [ ] Billing tiers, if retention supports them
- [ ] Certificate pinning (needs backup pins and a rotation plan — Let's Encrypt leaf pins will break the app)
- [x] **Expired claimed care-links permanently lock out the caregiver's
      account** — fixed and deployed. `claim_care_invite` and
      `create_care_invite` now self-heal the caller's own expired
      `pending`/`claimed` rows before their guard checks run
      (`20260908120000_claim_invite_selfheals_stale.sql`), verified against
      `local_harness.sql` and pushed to the hosted Supabase project.
      [Issue #101](https://github.com/sagnikdas/medicyn/issues/101) /
      [PR #102](https://github.com/sagnikdas/medicyn/pull/102).

### iOS
Not shipped — but not "none of it built" either; that was stale. Re-audited
from the code on 2026-09-10, not from comments: an adaptive Cupertino/
Material layer already covers the app shell, navigation, dialogs, and time
pickers; `notification_service.dart` has iOS-specific scheduling logic (a
60-slot pending-notification budget, a rolling window for every-X-hours
schedules, reminder-category actions); `flutter build ios --release
--no-codesign` succeeds locally; and the app runs correctly on an iOS
Simulator (Supabase initializes, onboarding renders correctly, screenshotted).
Full parity audit, task-by-task plan, and a real-device QA script:
[`docs/ios/FEATURE_PARITY.md`](ios/FEATURE_PARITY.md),
[`docs/ios/IMPLEMENTATION_PLAN.md`](ios/IMPLEMENTATION_PLAN.md),
[`docs/ios/REAL_DEVICE_QA.md`](ios/REAL_DEVICE_QA.md). iOS still ships to the
same bar Android already meets — reminders that fire with no network and no
live app process — and that specific claim remains unverified on real
hardware (see below).

- [x] Push notifications, code side — found and fixed in
      [PR #119](https://github.com/sagnikdas/medicyn/pull/119): no
      `Runner.entitlements` existed at all (APNs registration would fail
      silently on a real device), `Info.plist` had no background mode to
      wake for a silent push, and the `notify-care` edge function's FCM
      payload had no `apns` block — a data-only `data_changed` re-arm ping
      would never have woken the app, and a visible missed-dose/refill alert
      would have arrived silent. All three fixed and tested (16/16 Deno
      tests). Delivery itself is still blocked on the Apple Developer Push
      Notifications capability + an APNs key uploaded to Firebase — both
      operator actions, not code.
- [ ] **Toolchain:** the vendored Google ML Kit framework has an x86_64
      simulator slice and an arm64 device slice but no arm64 simulator slice
      — a Google-side upstream limitation (confirmed still current, not a
      version pin this repo controls). The Podfile's existing x86_64-only
      simulator workaround still compiles, but no longer *installs* on this
      machine's iOS 26.3 Simulator runtime (Apple has since dropped x86_64
      Simulator support there); it installs and runs correctly on an iOS
      18.3 runtime. A real device is unaffected either way — the exclusion
      only touches the simulator SDK.
- [ ] Validate on a signed physical iPhone: camera/OCR, speech, local
      notifications and action buttons, permission prompts, Dynamic Type,
      dark mode, VoiceOver, encrypted database at runtime (`PRAGMA key`).
      None of this has run on real hardware yet — no iPhone has been
      available in any session so far. Script ready at
      [`docs/ios/REAL_DEVICE_QA.md`](ios/REAL_DEVICE_QA.md).
- [ ] Move the brand mark off the Android resource path — `MedicynBrandMark`
      (`medicyn_chrome.dart`) still points `Image.asset` at
      `android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png`. Renders
      correctly on iOS today regardless (Flutter bundles it as a plain
      asset; confirmed on Simulator) — this is a path-hygiene cleanup, not a
      functional gap.
- [ ] Apple Developer / App Store Connect account, team, certificates, profiles, app record, export-compliance classification
- [ ] iOS Google OAuth client — code side is ready
      (`GoogleAuthConfig.iosClientId`, and `Info.plist`'s `GIDClientID`/
      URL-scheme block is pre-written as a comment) and just needs a real
      client id from Google Cloud Console
- [ ] APNs key uploaded to Firebase (Firebase's iOS app registration and the
      Crashlytics dSYM upload phase are already done — see Live
      infrastructure, above)
- [ ] Final branded AppIcon artwork — the asset slot is populated, but with
      Flutter's default logo, not Medicyn's (confirmed by opening the file)
- [ ] Final App Store screenshots and copy

### Compliance operator actions
- [ ] Accept each processor DPA (Supabase, Anthropic, Google FCM / Sign-In); request Anthropic zero-retention. Platform speech is a Google controller relationship — no DPA to sign
- [ ] Decide EU/UK region vs SCC paperwork — database is still `ap-southeast-1`
- [ ] Appoint an Art. 27 EU representative before an EEA Play listing, or restrict countries
- [ ] Re-read the DPIA before Play release; update if the four flows
      change — now also owed a real re-read because the controller changed
      from Sagnik Das to Doezly on 2026-09-08 (noted inline in
      `compliance/pack/DPIA.md`, not yet actually re-assessed)
- [ ] Keep the ROPA in step when a processor or purpose appears
- [x] Host MHMD policy on a public URL — live at `medicyn.doezly.com/mhmd`,
      verified. Still gated on the actual decision to enable Washington
      distribution, which is separate from whether the page exists.
- [x] ~~Resolve the `PRIVACY.md` duplication~~ — verified already resolved:
      `docs/compliance/PRIVACY.md` is a symlink to `app/assets/PRIVACY.md`
      (added in #71, "so drift is no longer possible"). The doc's claim of
      "byte-identical with no generator" was stale.

### Decisions needed
- [ ] Grace period before a dose counts as missed — flat 30 minutes today, probably wants to be per-medicine
- [ ] What happens when a link is broken and remade (e.g. a sibling taking over)
- [ ] Play Billing vs web checkout for the caregiver subscription
- [ ] Whether a lapsed caregiver can still see the read-only feed
- [ ] India GST and Play's price template
- [ ] Whether refill tracking stays free (default: yes)
- [ ] Refill basket (N1) monetization — resolve before building: neutral transparency, sorted by price alone, affiliate status disclosed on the row, revenue never reorders the list
- [ ] F5 interaction checking — needs an explicit go/no-go: Claude-based screening with disclosure, vs. blocked pending a licensed clinical source and legal review
- [x] ~~F7's multi-person view and F9's family pricing both require reversing the 1:1 care-link lock~~ — resolved 2026-09-11: direction accepted as one caregiver, up to two parents (see Locked decisions); building it is still open work, tracked under F7/F9

---

## Known gaps and limitations

Real limits in what is already merged. None are bugs; all are choices worth
remembering. Reviewed point-by-point on 2026-09-08; fixes for the three
marked below are tracked in
[issue #96](https://github.com/sagnikdas/medicyn/issues/96), everything else
here was deliberately kept as-is.

- **A sweep forfeits backfill from before a schedule was last edited.**
  `MissedDoseDetector.wasArmed` bounds every occurrence on the schedule's
  `updatedAt`, because the alarms actually armed on the device reflect its
  *current* definition. Without that bound, adding a 9am reminder reported
  three days of 8am doses as skipped — nine of the eleven missed doses in the
  live database were fabricated that way, and each would have been a
  notification on a family member's phone. Sweeps run on every foreground, so
  in practice almost nothing is lost, and silence beats a false alarm. The
  cost is that *any* edit resets this, including a cosmetic one (a spelling
  fix) that never changed what alarms actually fired. **Fix tracked in #96:**
  split a new `timingDefinedAt` from `updatedAt` so only a timing-relevant
  edit resets the anchor.
- **Every-X-hours doses share one lattice** between the alarm scheduler and
  missed-dose detection (`intervalDoseSequence`). The origin is the calendar
  day of `updatedAt`, so the same `wasArmed` rule applies, and the same #96
  fix covers it.
- **A missed dose is only noticed while the parent's app runs.** The sweep is
  device-side, on foreground. A parent who does not open the app for two days
  generates no missed doses and therefore no alerts. A `device_silent` alert
  path already exists end-to-end (client heartbeat, RPC, push copy) but
  nothing ever calls it — no scheduler exists in the repo. **Fix tracked in
  #96:** an hourly GitHub Actions workflow to invoke it.
- **A caregiver's edit re-arms the parent's alarms** via the silent
  `data_changed` push, but the parent's phone still has to be reachable by
  FCM. Offline or force-stopped, the change sits until the next foreground
  pull. Reviewed and kept as-is: the failure modes (no connectivity, a
  force-stopped app) are outside what any push mechanism can fix, and the
  send path already uses FCM high priority and the default long TTL.
- **A missed-dose alert waits for connectivity.** It is late by however long
  the phone stays offline, not by minutes. Reviewed and kept as-is.
- **An alert is only offered for 24 hours** (`CareNotifier.announceWindow`).
  A dose missed longer ago is in the feed but will never ring a phone.
  Reviewed and kept as-is.
- **The parent is told nothing when an alert fires.** Resolved: a gentle
  in-app banner on the Today screen when one of the parent's own doses is
  logged missed, worded as a supportive nudge rather than a report that the
  caregiver was told. **Fix tracked in #96.**
- **Sibling sharing is impossible** by design. Nobody can be both a parent
  and a caregiver in different pairs.
- **Voice input is not on-device.** `SpeechListenOptions.onDevice` is false,
  so the platform recogniser handles it and on most Android devices Google's
  servers see the audio. The privacy policy says so plainly. Setting it true
  fails outright on devices with no offline model.
- **The `deleted` column** on `medicines` and `schedules` is dead — never
  set, absent from Postgres, superseded by `active = false`.
- **The timestamp correction assumes every row predates the fix.** It shifts
  by each owner's `profiles.timezone`, so it must be applied once and only
  after every device sends UTC. Rows whose owner has no recorded timezone are
  left alone rather than guessed at.
