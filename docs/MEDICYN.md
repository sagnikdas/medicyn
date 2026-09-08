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
- [ ] Formatted PDF

### F7 — Virtual caregiver dashboard
- [x] Dose feed
- [x] Patient-reminders view and editing
- [x] Phone dial
- [x] Device-health panel
- [x] Change history
- [ ] Caregiver-side trends
- [ ] Multi-person view (blocked — care link is locked 1:1)
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
- [ ] **F9 — Family plan pricing on care links.** Needs multi-link schema,
      which the 1:1 lock forbids today.
- [ ] **F10 — Premium caregiver dashboard.** Foundation only.
- [ ] **F11 — "Ask about my meds" assistant.** Same Claude pipe, new prompt.

### New — accepted, not started

Selected from a healthcare-gap review (September 2026). Scope rule: only
ideas that fall out of data Medicyn already holds, or point the existing
camera at different paper.

- [ ] **N1 — Refill basket.** Collapse per-medicine warnings into one list on
      one date a month. Plugs into `refill.dart`,
      `Medicines.tabletsRemaining`; no schema change needed.
- [ ] **N2 — Tests that are due.** The monitoring a regimen implies
      (levothyroxine → TSH, warfarin → INR, metformin → HbA1c, statin →
      lipids + LFT). Plugs into `insights_screen.dart`, `TodayCareReminders`.
- [ ] **N3 — Emergency card.** Medicines, doses, allergies, conditions, blood
      group, caregiver's number. Plugs into `data_export_service.dart`,
      Profile.
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
- [ ] N3 must not be a lock-screen surface — one tap from Profile, plus a
      printable copy.
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
| Care link cardinality | One caregiver per parent. |
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
- [x] **Firebase** (`decent-digit-135023`): Android app registered, service account stored as `FCM_SERVICE_ACCOUNT` secret

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
- [ ] Fill the three placeholders in `compliance/PRIVACY.md` (effective date and support email, two places)
- [ ] Host the policy at a public URL
- [ ] Enable GitHub Pages and verify published policy, deletion and MHMD URLs
- [ ] Release keystore and `app/android/key.properties` (see `app/README.md`)
- [ ] Play Console Data safety form, matching `compliance/PRIVACY.md` (answers prepared in `compliance/pack/PLAY-DATA-SAFETY.md`)
- [ ] Complete the Play declaration for `SCHEDULE_EXACT_ALARM`
- [ ] `flutter build appbundle --release`, upload to internal testing
- [ ] Register an Android OAuth client for each SHA-1 Play shows (app signing key and upload key), add both to Supabase Client IDs
- [ ] Closed testing for the required period
- [ ] Store listing written to the caregiver child, not the parent
- [ ] Overlay-install verification on the Galaxy M33

### Product gaps — before broad acquisition
- [ ] System accessibility scaling — the app overrides Android's own
      text-size preference with an in-app scaler capped at 150%
      (`app/lib/main.dart:104-107`); some controls are also undersized
- [ ] Add-method chooser and shorter onboarding ("scan or speak" as a real choice)
- [ ] Sync and family-delivery status visible to the user
- [ ] As-needed logging, pause/completion, corrections
- [ ] Complete export and locale-aware dates
- [ ] Insights calculation and accessibility fixes
- [ ] Refill workflow (superseded in shape by N1)

### Product gaps — after a successful launch
- [ ] Multiple caregivers / multiple patients, and escalation
- [ ] PDF clinician report (F6's missing half)
- [ ] Travel assistant; home-screen widget
- [ ] Billing tiers, if retention supports them
- [ ] Certificate pinning (needs backup pins and a rotation plan — Let's Encrypt leaf pins will break the app)
- [ ] Auto-revoke stale `claimed` care links

### iOS
Scoped, none of it built. iOS ships to the same bar Android already meets —
reminders that fire with no network and no live app process.

- [ ] **Toolchain blocker:** the vendored Google ML Kit framework has an
      x86_64 simulator slice and an arm64 device slice but no arm64 simulator
      slice — an Apple-Silicon simulator can't link it
- [ ] Validate on a signed physical iPhone: camera/OCR, speech, local
      notifications and action buttons, permission prompts, Dynamic Type,
      dark mode, VoiceOver, encrypted database at runtime (`PRAGMA key`)
- [ ] Move the brand mark from the Android resource path to a shared Flutter branding asset
- [ ] Apple Developer / App Store Connect account, team, certificates, profiles, app record, export-compliance classification
- [ ] iOS Google OAuth client and Firebase/APNs configuration
- [ ] Final branded AppIcon artwork
- [ ] Final App Store screenshots and copy

### Compliance operator actions
- [ ] Accept each processor DPA (Supabase, Anthropic, Google FCM / Sign-In); request Anthropic zero-retention. Platform speech is a Google controller relationship — no DPA to sign
- [ ] Decide EU/UK region vs SCC paperwork — database is still `ap-southeast-1`
- [ ] Appoint an Art. 27 EU representative before an EEA Play listing, or restrict countries
- [ ] Re-read the DPIA before Play release; update if the four flows change
- [ ] Keep the ROPA in step when a processor or purpose appears
- [ ] Host MHMD policy on a public URL if Washington distribution is enabled
- [ ] Resolve the `PRIVACY.md` duplication — `docs/compliance/PRIVACY.md` and
      `app/assets/PRIVACY.md` are byte-identical with no generator between
      them; one source, generated or symlinked

### Decisions needed
- [ ] Grace period before a dose counts as missed — flat 30 minutes today, probably wants to be per-medicine
- [ ] What happens when a link is broken and remade (e.g. a sibling taking over)
- [ ] Play Billing vs web checkout for the caregiver subscription
- [ ] Whether a lapsed caregiver can still see the read-only feed
- [ ] India GST and Play's price template
- [ ] Whether refill tracking stays free (default: yes)
- [ ] Refill basket (N1) monetization — resolve before building: neutral transparency, sorted by price alone, affiliate status disclosed on the row, revenue never reorders the list
- [ ] F5 interaction checking — needs an explicit go/no-go: Claude-based screening with disclosure, vs. blocked pending a licensed clinical source and legal review
- [ ] F7's multi-person view and F9's family pricing both require reversing the 1:1 care-link lock

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
