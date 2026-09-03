# Product

<!-- impeccable:product-schema 1 -->

## Platform

android

## Users

Two distinct users, one purchase (see Positioning):

- **The parent/patient (primary user).** An elderly person taking one or
  more medications. They photograph the label, say the dosage/schedule out
  loud, review the AI's interpretation, and tap Taken/Snooze on the
  notification. They will not search Play for this, will not enter a card,
  and will abandon anything that looks like a bill, a login maze, or a
  lecture. Small-form-factor typing is a real friction point for this
  audience — it's the reason the capture flow leads with a photo and a
  spoken sentence instead of a form.
- **The adult-child caregiver (secondary user, the paying customer).**
  Lives in another city from the parent. Discovers the app, installs it on
  both phones, links via invite code, and watches the dose feed. They lie
  awake wondering whether a dose was taken; the product's entire caregiver
  half (missed-dose alerts, remote editing, call-from-alert) exists for
  them.

Exactly one caregiver per parent today (`care_links` is 1:1); a sibling or
second parent is explicitly out of scope until multi-link support ships.

## Product Purpose

A minimalist medicine reminder that removes manual data entry (photo of the
label + spoken dosage, structured by Claude into an editable form) and
fires reminders reliably with zero dependency on network or a live app
process (on-device exact alarms, local SQLite as the source of truth for
*when* things fire). Success is a parent who keeps the app installed and
opened because it never nags, never fails silently, and never asks them to
type — and a caregiver who trusts the missed-dose alert enough to stop
calling to check.

## Positioning

The only medication reminder that combines AI-parsed photo+voice capture
with true pharmacy-agnostic tracking and offline-first alarm firing, paired
with real two-way caregiver alerts (missed-dose push to the caregiver,
silent re-arm push back to the parent). This differs from every researched
competitor on a specific axis:

- **Retail apps** (Amazon/PillPack, CVS MedRemind, Walgreens) are locked to
  medications that pharmacy filled. Medicyn has no pharmacy-system
  dependency at all — capture is a photo of any label from any source.
- **Medisafe, MyTherapy, Dosecast, CareZone** all require manually typing
  the medication name, dosage, and schedule — the single biggest friction
  point for an elderly user. None combine AI label-reading with
  voice-based dosage confirmation in one flow.
- **Hero** sells the same caregiver-visibility outcome ("is my parent on
  track") through a $30–60/month hardware dispenser. Medicyn generates the
  equivalent signal in software from the confirmation loop, at a fraction
  of the cost, with no hardware to ship or fail.

Monetization follows the split: the parent's core loop (scan, speak, save,
alarm — fully offline, no account required) is free forever; the caregiver
pays for the care pair (missed-dose alerts, setup health, remote edit,
call-from-alert). No pricing exists yet — deliberately deferred until real
adoption evidence exists (see Capabilities and Constraints).

## Operating Context

**Capture loop:** camera photo of the label → on-device ML Kit OCR (photo
discarded immediately, only text leaves the camera screen) → spoken
dosage/schedule captured via speech-to-text (Google's recognizer on most
Android phones — audio may leave the device) → OCR text + transcript sent
to a Supabase Edge Function that asks Claude to structure drug name,
strength, dose, frequency, and times → editable review form → nothing
saved until the user taps Save.

**Firing:** an exact alarm is scheduled directly on the device the moment a
reminder is saved (Drift/SQLite is the source of truth), re-armed on every
app foreground so any OEM battery-manager interference self-heals. This is
never in the firing path: Supabase is backup/sync only, and the alarm fires
with zero connectivity.

**Care link:** invite code → claim → explicit named-person confirmation
(possession of a code is never access) → full-symmetry visibility (parent
sees exactly what the caregiver sees) → either side can add/edit
medicines, only the parent can delete → conflicts resolved last-write-wins
on a client-stamped `updated_at`, made safe by showing who changed what.
Two distinct pushes travel the link: a **visible** "missed a dose" alert
(parent → caregiver) and a **silent** re-arm ping (caregiver → parent,
after a remote schedule edit) — both through one `notify-care` edge
function called by the device, not a database trigger. Missed-dose grace
period is 30 minutes.

**Auth:** Google Sign-In only (native account picker, ID-token exchange
with Supabase; no browser, no email/OTP). An account is required only for
backup and family sharing — reminders work fully local-only without one.

**Distribution:** Android via Google Play (package `com.sagnikdas.medicyn`,
API 24+). iOS is not started.

## Capabilities and Constraints

**Built and shipped:** photo+voice AI capture; offline exact-alarm firing;
1:1 care links with invite/claim/confirm/disconnect; caregiver dose feed;
missed-dose detection and two-way push; caregiver remote editing with
per-medicine change history; refill tracking with a 5-day-out low-stock
warning; GDPR Art. 15/20 data export and account deletion; device-credential
(PIN/pattern/biometric) re-lock on the caregiver's dose feed so medicine
names never show on a locked screen.

**Not yet built (do not imply otherwise in new UI copy):** drug-drug
interaction warnings; a doctor-ready PDF adherence export (JSON export and
an in-app weekly-adherence Insights screen exist; the formatted PDF does
not); multi-caregiver or multi-patient links; any payment/paywall code —
none exists anywhere in the repo; an "ask about my meds" assistant; Medicare
RTM billing; pharma data licensing (deliberately deferred — needs ~100K+
users and currently conflicts with the privacy stance).

**Regulatory constraints that shape what can be built or claimed:** HIPAA
does not currently apply (no covered-entity or business-associate
relationship — every field is user-entered, no provider/EHR/billing
integration). GDPR/UK GDPR, the FTC Health Breach Notification Rule,
Washington's My Health My Data Act, CCPA/CPRA, and Google Play's Health
apps policy all bind the product today. A future clinic/payer/EHR
integration would newly trigger HIPAA and is out of scope absent that
decision being made explicitly.

**Terminology:** "care link" (the caregiver↔parent pairing), "dose feed"
(the caregiver's read of adherence), "setup health" (whether the parent's
notification/battery permissions are actually letting alarms fire).

**Undecided, on purpose:** pricing and paywall timing — first public
version ships free; charging starts only after organic evidence that pairs
form and stay, not on a launch-day hypothesis.

## Brand Commitments

Product name is **Medicyn** (renamed from Dosely, September 2026 — the
Supabase project ref and org stay unchanged under the old slug on purpose).
Solo developer and data controller: Sagnik Das (sagnikd91@gmail.com) — no
other contact address exists, and no company/team identity is implied
anywhere in-product. Typeface already committed and bundled: **Public
Sans** (variable font, `app/assets/fonts/PublicSans-Variable.ttf`). Binding
promises already made in the shipped privacy policy and must not be
contradicted by new work: no ads, ever; no sale or licensing of health
data; local-only use is always available with no account required.

## Evidence on Hand

No real customer testimonials, case studies, press, or usage statistics
exist yet — the product has zero customers today by design docs' own
description, and both the hosted Supabase project and the developer's test
device have been cleared of test data (the home screen shows its true
empty state). Do not fabricate user quotes, family counts, adoption
numbers, or clinical claims in any new surface. If drug-interaction
checking is ever built, it must ship with an explicit "AI-generated
screening, not a clinical database" disclosure (per
`docs/product/DRUG-INTERACTIONS.md`) rather than being presented as
authoritative.

## Product Principles

1. The parent's phone must never feel like a bill, a login maze, or a
   lecture — the free core loop (scan, speak, confirm, alarm) works with
   zero account and zero connectivity, full stop.
2. Reminders fire from the device itself. Cloud and push exist to carry
   news *between* two phones — never to arm or gate a reminder.
3. The caregiver relationship is symmetric and consensual: full visibility
   both directions, two-step consent to link, and the caregiver can add or
   edit but never delete.
4. No health data leaves the phone except for the two named jobs
   (structuring a label+voice capture, syncing for backup/care) — no ads,
   no data sale, ever.
5. Elderly/senior usability is the design constraint the whole product is
   built around, not an accommodation bolted on afterward.

## Accessibility & Inclusion

Formal bar: **Android's own accessibility guidelines** — TalkBack support,
Android's touch-target and contrast guidance, and passing Google Play's
accessibility checks — applied to every screen, chosen because the primary
user is frequently an elderly person for whom this is not an edge case.

Known open gap (tracked as a bug, not yet fixed): the app currently
overrides the system accessibility font-scaling preference with its own
in-app scaler capped at 150% (`app/lib/main.dart:104-107`), so a user who
set larger text at the Android level does not get it by default in
Medicyn; some controls are also undersized per the 2026-08-26 UX audit.
New design work should not repeat this pattern.
