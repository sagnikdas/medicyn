# Dosely — HIPAA and GDPR compliance plan

A phased plan to close the gap between what Dosely does today and what the law
requires of it. Audited against `main` @ `006489f`, 2026-08-19.

Read the threshold finding first. It changes what the rest of this document is
for.

---

## Threshold finding: HIPAA does not currently apply. GDPR does.

**Dosely is neither a Covered Entity nor a Business Associate.** HIPAA reaches
health plans, clearinghouses, and providers who transmit health information in
connection with a covered transaction (45 CFR 160.103) — plus Business
Associates acting on their behalf. Dosely is none of these:

| Test | Finding |
|---|---|
| Provider, pharmacy, EHR or HIE integration? | None. The complete outbound surface is Supabase, `api.anthropic.com`, FCM, and Google Sign-In. No FHIR, no HL7, no e-prescribing. |
| Billing, claims, or eligibility transaction? | None. No payer, member ID, NPI, CPT or ICD field exists anywhere in the schema. |
| Does health data originate from a covered entity? | No. Every field is user-entered — a photo the user takes, a sentence they speak, a form they edit before saving. |
| B2B contract with a plan, clinic, or provider? | None. No tenancy or org concept; distribution is consumer Google Play. |

Dosely holds **consumer-generated health information outside the HIPAA-regulated
flow** — the same legal posture as a fitness tracker or a paper pill diary.
Building "HIPAA compliance" as the primary goal would be spending real effort
against the wrong statute.

### What *does* bind Dosely today

- **GDPR / UK GDPR** — squarely, for any EU or UK user. Medication and adherence
  data is Article 9 special-category health data. This is the real obligation
  and it is where the work should go.
- **FTC Health Breach Notification Rule (16 CFR 318)** — the 2024 amendments
  explicitly cover non-HIPAA health apps, and define "breach" to include *any*
  unauthorised disclosure, not just intrusion.
- **Washington My Health My Data Act** — "consumer health data" expressly
  includes medications. Requires a *separate* consumer health data privacy
  policy, opt-in consent before collection, a second consent before sharing,
  and it carries a **private right of action**. Nevada SB370 is similar.
- **CCPA/CPRA and the state privacy laws** — health data is sensitive personal
  information requiring opt-in and a limitation right.
- **Google Play** — Health apps policy, the Data Safety form, and the mandatory
  account-deletion path (in-app *and* a web URL). This blocks release.

### What would pull Dosely into HIPAA

Any of: an EHR or provider integration; a B2B deal selling into a clinic,
health system, home-health agency or payer (Dosely becomes a Business
Associate); reimbursement for remote monitoring; or employing a clinician.

**So this plan is structured as: fix what binds you now (Phases 1–3), then
HIPAA *readiness* as a distinct, deferrable track (Phase 4).** The good news is
that the HIPAA Security Rule work is largely a superset of what GDPR Art. 32 and
FTC reasonableness already demand, so Phases 1–3 do most of it. The *documents*
differ and cannot be substituted — an MHMD consumer health data policy is not a
HIPAA Notice of Privacy Practices.

---

## What is already good

Worth stating plainly, because it means most findings below are missing surface
rather than broken foundations:

- RLS on every table, routed through a single `can_access_user_data()`
  chokepoint, with 34 adversarial SQL assertions
- Security-definer functions with `search_path` pinned to `public, pg_temp`
- `care_links` and `care_alerts` have no insert/update/delete policies at all —
  state changes can only go through vetted RPCs
- Notification content is composed server-side from the database, so a stolen
  session cannot forge what a family is told
- `notify-care` re-verifies the JWT against the auth server rather than
  trusting the gateway flag
- No analytics or advertising SDKs of any kind
- The label photo is deleted immediately after on-device OCR
- The caregiver's client stores nothing locally, so erasure at source is
  actually effective
- `PRIVACY.md` volunteers the inconvenient truth about the Google speech
  recogniser, which most apps hide

The gaps concentrate in two places: **the device**, where almost nothing has
been hardened, and **governance**, where nothing exists yet.

---

## Phase 1 — Blockers

Nothing ships to an EU or UK user, and nothing goes to Play, until these are
done. Each is either a legal precondition or a one-line fix with a large blast
radius.

### 1.1 Disable Android auto-backup — **one line**

`app/android/app/src/main/AndroidManifest.xml` declares no `android:allowBackup`,
no `android:dataExtractionRules`, and no `android:fullBackupContent`. The
platform default is `true`.

Verified live on a physical Samsung SM-M336BU (Android 15): Backup Manager is
enabled, the active transport is `com.google.android.gms/.backup.BackupTransportService`,
and `com.sagnikdas.dosely` is a registered backup participant. The unencrypted
medicine database and the plaintext Supabase refresh token are both eligible for
upload and for device-to-device transfer.

Google's cloud backup is client-side encrypted against the device screen lock,
which limits exposure to Google itself — but this remains an undisclosed
disclosure and transfer under GDPR Art. 13(1)(f)/44, and the D2D transport
copies it to any new phone.

**Fix:** `android:allowBackup="false"`, plus `dataExtractionRules` excluding the
Drift file and shared preferences as defence in depth.

### 1.2 Wipe the local database on sign-out — **small change, largest exposure closed**

`AuthService.signOut()` (`app/lib/features/auth/auth_service.dart:137-152`)
clears the Supabase and Google sessions and unregisters the FCM token. It never
touches `appDatabase`.

**Verified on the device:** the local schema has **no `user_id` column on any
table** — `medicines`, `schedules`, and `dose_logs` are scoped only by `active`
and `deleted`. The attached phone currently holds 1 medicine, 1 schedule and 4
dose logs, all recoverable as plaintext.

So when a second Google account signs in on the same phone — precisely the
shared-device scenario this product targets — the home screen renders the
*previous* user's medicines and the notification engine re-arms their alarms.
The sign-out dialog states this as a feature: *"Your reminders stay on this
device either way"* (`app/lib/features/settings/settings_screen.dart:132`).

Note the irony: `device_tokens` was deliberately keyed by the token itself to
stop a handed-back phone receiving the previous person's alerts. The health
database, far more sensitive, has no equivalent protection.

**Fix:** wipe the Drift database on sign-out and correct the dialog copy. The
server holds the backup, so wiping is the simple and correct option.

### 1.3 Build the consent flow — **the central GDPR gap**

There is no consent capture anywhere in the app. `grep -rni "privacy|consent|policy" app/lib`
returns only source comments. `PRIVACY.md` is never rendered, linked, or
referenced by any screen. Onboarding
(`app/lib/features/onboarding/onboarding_screen.dart:23-39`) is three marketing
pages and a **Skip** button, and persists exactly one flag.

Article 9(1) prohibits processing health data unless a 9(2) condition applies.
The only available one is 9(2)(a) explicit consent — not obtained, not recorded,
not demonstrable under Art. 7(1). **Every processing operation is currently
unlawful for EU/UK data subjects.**

**Fix:** a consent screen between the onboarding and auth gates, with
**separate, unticked** controls — not one blanket accept:

- store medicines and dose history in cloud backup
- send label text and spoken description to Anthropic (US)
- use the phone's Google speech recogniser (audio leaves the device)
- share health data with a linked caregiver — taken separately, at link time

Persist a `consents(user_id, purpose, granted_at, withdrawn_at, policy_version,
consent_text_hash, app_version)` table written through a security-definer RPC,
in the same shape as `register_device_token`. Add a "Manage what Dosely can do"
section in Settings where each toggle is as easy to withdraw as it was to give
(Art. 7(3)).

### 1.4 Unbundle consent from access to the app

Sign-in is mandatory (`app/lib/main.dart:133-145`), so a user cannot get
reminders without consenting to cloud storage of health data. That is the
textbook Art. 7(4) conditionality failure and it invalidates the consent in 1.3.

The architecture already supports the fix: `README.md` states local Drift is the
source of truth and Supabase is backup only.

**Fix:** add a local-only mode that skips sign-in entirely, with sync and Care
Link offered later as opt-in.

### 1.5 Build account deletion

Traced end to end: nothing in the app, no RPC, no edge function. The only
account action is Sign out. `PRIVACY.md:132-138` directs users to email an
address that is still `_[FILL IN]_`.

The Postgres side is one manual action from correct — `on delete cascade` from
`auth.users` holds across every table. The local Drift database is never deleted
at all.

This fails GDPR Art. 17, CCPA, MHMD (which requires propagation to processors),
and **Google Play's account-deletion policy, which blocks release**.

**Fix:** a `delete_account` edge function under the caller's JWT — revoke any
live care link, delete `device_tokens`, then `auth.admin.deleteUser(uid)` and let
the cascades run. In-app entry point with a two-step confirm. Wipe the local DB.
Publish a deletion-request web URL.

### 1.6 Fix the Care Link consent prompt — it cannot name the person it is asking about

This defeats the security property the whole design rests on: *possession of a
code is never access; the parent confirms the named person.*

At the confirmation moment the patient **cannot read the claimant's name**:

- `care_screen.dart:292` renders `_otherName ?? 'Someone'` → *"Someone typed in
  your number"*, button *"Yes, connect with Someone"*
- `_otherName` comes from `CareService.displayName()`, a plain select on `profiles`
- the `profiles_read` policy
  (`supabase/migrations/20260818161500_care_links.sql:138-147`) requires
  `status = 'active'` on both branches
- at confirmation the link is `status = 'claimed'`, so the select returns empty
  and the client's `?? 'Someone'` fallback hides the failure

The RLS is behaving exactly as intended. The defect is that the *consent UI*
depends on a read the *security model* forbids.

**Compounding it:** the invite code is 6 digits (keyspace 10^6) and
`claim_care_invite` has no per-caller rate limit. Alone, neither is critical —
the design correctly says the code is not the security boundary, the
confirmation is. **Together they compose**: sweep for a live code, claim it, and
the patient sees an unnamed prompt they may well accept while expecting their
daughter's claim.

**Fix:** a security-definer RPC returning only the claimant's display name *and
email* for a `claimed` link where `auth.uid()` is the patient — a deliberate
one-field disclosure rather than widening `profiles_read`. Show the email; a
self-asserted Google display name is weak identity proof. **Fail closed**: block
confirmation when no name resolves. Separately, rate-limit `claim_care_invite`
and lengthen the code.

### 1.7 Fill the privacy policy placeholders and publish

`PRIVACY.md:3`, `:4`, `:162` are `_[FILL IN]_` — effective date, controller
legal name and postal address, support email. Every other obligation in this
document depends on a reachable contact, including the 72-hour breach clock.

Publish at a stable URL and link it from the sign-in screen, the consent screen,
and Settings. A policy that exists only as a repo file does not satisfy
Art. 12(1) — the information must reach the user at the point of collection.

**Exit criteria for Phase 1:** consent recorded before any health data is
written; a user can delete their account from inside the app; nothing leaves the
device to Google backup; a signed-out phone holds no health data; the care-link
prompt names a real person or refuses to proceed; the policy is published and
linked.

---

## Phase 2 — Rights, retention, and honest documentation

### 2.1 Rewrite `PRIVACY.md` against Article 13

The policy reads well and is unusually honest, but is missing over half the
mandatory elements. Failing: legal bases (never stated), **international
transfers (no mention at all — all three recipients are US)**, retention periods
("as long as your account exists" is not a period), five of the six data subject
rights, the right to withdraw consent, the right to complain to a supervisory
authority, whether provision is required, and the automated-decision-making
statement.

On that last one: Claude structuring a schedule is **not** Art. 22
decision-making, because a human reviews and confirms every field. Say so —
users reasonably assume otherwise about an "AI" step.

### 2.2 Correct two claims the code does not implement

- *"Both of you can see that record"* / *"you can see every alert Dosely has
  sent them"* (`PRIVACY.md:37-39`, `:103`). No screen queries `care_alerts` —
  the RLS permits the read but no UI exercises it. `PLAN.md` confirms: "The
  parent is told nothing when an alert fires." Either build the screen (a
  UI-only change, the policy is already in place) or delete the claim.
- *"deleted when you sign out"* of the FCM token
  (`PRIVACY.md:33`). `PushService.unregisterToken()` returns early twice and
  swallows every exception — it is best-effort. Soften the wording.

### 2.3 Disclose what is actually collected

`PRIVACY.md:40-42` says Dosely collects no location or device identifiers.
Undisclosed: the IANA **timezone** written to `profiles` on every sign-in
(coarse location, and shared with the caregiver), **`last_seen_at`**, and the
**Firebase Installation ID**. Qualify the sentence to "advertising identifiers"
and list the rest.

Also correct `README.md:13`, which says speech is "transcribed on-device". It is
not, and `PRIVACY.md` says so — a contradiction that becomes a misrepresentation
if the README text is reused in the store listing.

### 2.4 Implement data subject rights

Add a "Your data" section in Settings: **Download my data** (JSON/CSV export
covering medicines, schedules, dose logs, profiles, care links, alerts — this
satisfies Art. 15 and Art. 20 together), **Delete my account** (Phase 1.5), and
**Manage consents** (Phase 1.3). Document the one-month Art. 12(3) clock.

Dose logs are immutable by design, which is defensible — but there must be a
route to contest an entry, because the app has already written provably
fabricated missed doses. Allow a user correction note attached to a log rather
than mutating it.

### 2.5 Fix "Remove this reminder", which removes nothing

`home_screen.dart:140-157` sets `active = false`. The medicine row is never
touched, and the caregiver's feed joins schedules regardless of `active` — so a
"removed" reminder's dose history stays visible to the caregiver indefinitely.

Either implement true deletion, or rename the action "Stop reminding me" and add
a separate "Delete this medicine and its history".

### 2.6 Retention periods and a prune job

No TTL, no cron, no archival anywhere. `dose_logs`, `care_alerts`, revoked
`care_links` and `device_tokens` all grow without bound.

Define, publish, and implement: dose logs 24 months rolling; `care_alerts` 12
months; revoked `care_links` 12 months (justified as an audit of who had
access); `device_tokens` 90 days without refresh — `refreshed_at` already exists.

### 2.7 Scope revoked-caregiver access

`care_alerts_read_own_link` has no status filter, so a disconnected caregiver
keeps permanent read access to every alert row for that link — a durable record
of which dates the patient missed doses. `PRIVACY.md:114-118` tells the user
"access stops immediately", which is true of medication data and not of alert
history.

**Fix:** `patient_id = auth.uid() OR (caregiver_id = auth.uid() AND status <> 'revoked')`.

Related: `confirm_care_link` never checks `expires_at` and nulls it on success,
so a link claimed by the wrong person sits in the patient's app indefinitely,
re-presenting the confirm prompt every 4 seconds until someone mis-taps. Add the
expiry check and lazily revoke stale `claimed` links.

**Exit criteria for Phase 2:** the policy is accurate and complete; a user can
export and delete their data from inside the app; every table has a retention
period and a job that enforces it; revocation actually revokes.

---

## Phase 3 — Governance and paperwork

No code. All of it is mandatory, and none of it exists.

### 3.1 Data Protection Impact Assessment — mandatory

Under EDPB WP248, two criteria trigger a DPIA. Dosely hits five: special
category data; vulnerable data subjects (the design target is explicitly elderly
parents); disclosure to a third party with write access; innovative technology
(an LLM structuring health data); and risk of physical harm.

It must cover the four data flows, the necessity of sending the full OCR blob
and of the cloud speech default, the risk of **false reassurance** (a caregiver
reading "no alerts" as "all is well"), the risk of **false alarm** (the
fabricated missed doses), the risk of a **coercive caregiver** given write access
and no read-only mode, transfers, and whether an 80-year-old reading a six-digit
code over the phone is giving informed Art. 9 consent.

`PLAN.md`'s "Known gaps" section is already a better risk register than most
formal DPIAs. Lift it directly rather than starting fresh.

### 3.2 Processor contracts

| Processor | Receives | Action |
|---|---|---|
| Supabase | Everything | Execute the published DPA |
| Anthropic | Raw OCR text and verbatim transcript | Execute the commercial DPA; **request zero data retention**; confirm processor status in writing |
| Google (FCM) | Recipient token plus the full notification body — patient name, drug, strength, due time | Accept the Cloud/Firebase DPA in console |
| Google (speech) | Raw audio of the patient describing their medication | **Not coverable** — Google acts as controller. Needs consent (1.3) or `onDevice: true` |
| Google (Sign-In, Play) | Account identity, install data | Independent controller — disclose |

### 3.3 International transfers

`PRIVACY.md` has no transfer section.

**The Supabase database is in `ap-southeast-1` (Singapore)** — established
directly against the hosted project, and no longer an open question. Singapore
has no EU adequacy decision. Together with Anthropic and Google, all three
recipients of health data are outside the EEA and the UK, and not one transfer
has a documented safeguard.

Moving the project to an EU or UK region is the single cleanest fix and removes
the largest transfer entirely. It is also far cheaper now than after launch:
the data is small, and a region change means recreating the project rather than
flipping a setting. For Anthropic and Google, rely on the EU-US Data Privacy
Framework where each entity is certified, plus SCCs and the UK IDTA, and
complete a Transfer Impact Assessment per recipient.

### 3.4 Record of processing (Art. 30)

**The small-organisation exemption does not apply** — it is disapplied where
processing includes special categories. A ROPA is mandatory regardless of
headcount. Keep it as `pack/ROPA.md`.

### 3.5 Breach response

No detection, no plan, no reachable contact, no register. Art. 33(5) requires a
register of **all** breaches, including non-notifiable ones.

One incident is already on the record and appears undocumented: the timezone
corruption altered every client-stamped health timestamp in the live database,
and the fabricated missed doses inserted false health events — nine of eleven
live rows — each of which would have been transmitted to a caregiver once push
landed. Art. 4(12) includes "accidental alteration". Backfill a register entry
with a documented threshold assessment.

### 3.6 Representative, DPO, and market scope

Decide target markets first. If EEA distribution is wanted, appoint an Art. 27
EU representative; if not, restrict distribution in Play Console and say so. A
DPO is **not** required at this scale, but the policy must say so and give a
privacy contact anyway.

### 3.7 State-law documents

A **separate** Washington MHMD consumer health data privacy policy, with its own
link, naming Supabase, Anthropic and Google individually, with opt-in consent
before collection and a second consent before sharing. Nevada SB370 is
satisfied by the same document.

### 3.8 Play Data Safety

Must agree with a policy that is currently incomplete, so do it *after* 2.1.
Declare Health info as collected **and shared**; name, email, user IDs; device
identifiers including the FCM token and Firebase installation ID; and **Audio —
voice recordings**, because the mic path sends audio to Google even though
Dosely never stores it. Complete the Health apps declaration. Add
`USE_FULL_SCREEN_INTENT` to the restricted-permission declarations alongside the
exact-alarm ones already tracked in `PLAN.md`.

---

## Phase 4 — HIPAA readiness

**Defer until a B2B deal or provider integration is actually in prospect.** Start
it when a term sheet exists, not before. Phases 1–3 will already have done most
of the Security Rule work.

### 4.1 The keystone: a PHI access log

`grep -rn audit` across the repo returns **zero** hits. When a caregiver reads a
patient's full dose history, nothing anywhere records that it happened.
`can_access_user_data()` authorises the read and returns; it logs nothing.

This is the largest single piece of work here, and four separate obligations
depend on it: audit controls §164.312(b), accounting of disclosures §164.528,
breach detection §164.400 — **and the FTC HBNR, which binds today**. An
architecture that makes discovery impossible does not stop the 60-day clock.

Add an append-only `phi_access_log(actor_id, subject_id, table_name, row_ids,
action, occurred_at, via)` with no update or delete policy, populated from a
security-definer RPC wrapping caregiver-facing reads. Surface it as a "who has
looked at my records" screen — which also discharges the MHMD and CCPA access
rights, and closes `PLAN.md`'s open question about what the parent is told.

### 4.2 Business Associate Agreements

Every processor in 3.2 needs a BAA, not just a DPA. Supabase requires a **Team
plan or above** with the HIPAA add-on — not available on Free or Pro. Anthropic
offers one under commercial terms.

**One is unobtainable at any price:** the Android platform speech recogniser is a
consumer Google service with no BAA. If Dosely ever becomes a Business
Associate, voice capture must set `onDevice: true` with a hard fallback to typed
entry, or be removed.

### 4.3 Technical safeguards not covered by Phases 1–3

- **Encrypt the local database.** `app/lib/data/local/database.dart:20` uses
  drift's default `NativeDatabase` — a plain file. **Confirmed on the device:**
  the SQLite magic bytes read `SQLite format 3`, and word-like strings are
  recoverable with `strings(1)`. Move to `sqlcipher_flutter_libs` with the key in
  the Android Keystore.
- **Protect the session token.** The Supabase access JWT *and* refresh token sit
  in plaintext SharedPreferences under
  `flutter.sb-twybepxnqayypzljhcnx-auth-token` — confirmed on the device.
  `Supabase.initialize` passes no custom `localStorage`. Move to
  `flutter_secure_storage`.
- **Automatic logoff** §164.312(a)(2)(iii). `[auth.sessions]`, `timebox` and
  `inactivity_timeout` are all commented out in `supabase/config.toml`; with
  refresh token rotation on and no timebox, a session renews indefinitely. Add a
  device-credential unlock rather than a hard timeout — a 15-minute logout is a
  usability disaster for the target user.
- **Lock-screen exposure.** `notification_service.dart:157` sets
  `NotificationVisibility.public` and the title is the drug name plus strength.
  Confirmed on the device: both channels are `NO_OVERRIDE`, so the
  per-notification setting governs and drug names do render on a locked phone.
  This is a defensible usability decision for the patient's own alarm — but it
  should be a setting, and it should default to private for *care* alerts, which
  the recipient does not need to act on instantly.
- **Minimum necessary at the Anthropic call** §164.502(b). The full OCR blob is
  forwarded, capped only at 4,000 characters. A dispensed pharmacy label
  routinely carries the patient's name, address, date of birth, prescriber and
  Rx number — all captured by OCR, all transmitted, when only drug name,
  strength, form, dose and times are needed. Redact on-device before the text
  ever leaves the phone. **Do this before signing the Anthropic BAA** — a BAA
  over unredacted label text is a far larger commitment.
- **Certificate pinning / network security config** — absent. Low severity, but
  a device with an attacker-installed user CA can intercept.

### 4.4 Written policies

Risk analysis and risk management plan (the single most-cited OCR enforcement
failure), workforce security and sanction policy, incident response, contingency
plan with a tested restore, and security awareness training. Note that
`.secrets/db_password.txt` is gitignored but sits unencrypted on the dev
machine, and one Google account is the sole path to Supabase, Google Cloud and
Firebase — enable MFA and document a key rotation cadence.

---

## Sequencing summary

| Phase | Gate | Depends on |
|---|---|---|
| 1 — Blockers | No EU/UK user, no Play release until done | — |
| 2 — Rights and retention | Play Data Safety cannot be filled honestly until done | Phase 1 |
| 3 — Governance | DPIA before Play release; ROPA and DPAs immediately | Phase 2.1 for the policy |
| 4 — HIPAA readiness | Only when a B2B deal is in prospect | Phases 1–3 |

The cheapest high-value items are 1.1 (one line), 1.2 (small change, largest
exposure closed), and 2.7 (one predicate). The largest are 1.3 (consent flow),
1.5 (deletion), and 4.1 (the access log).

---

## Status against `feature/phase-4` (2026-08-20)

The body of this plan still describes the codebase as audited on 2026-08-19.
Closed items are **not** rewritten above. This table is the live tracker and
should be updated when a phase (or a Phase 1-style blocker) closes. Phase 2
landed on `main` as #47. Phase 3 paperwork landed on `main` as #48. Phase 4
technical leftovers (4.3c–e) live on this branch until it is merged to `main`.

| # | Change the application needs | Kind | Status | Notes |
|---|---|---|---|---|
| 1.1 | `allowBackup="false"` + backup / D2D exclude XML | App | **Done** — #22 | Verified on the Galaxy M33. |
| 1.2 | Wipe local DB on sign-out so a second Google account cannot see the previous person's medicines | App | **Done differently** — #33 | Not a wipe: encrypted `dosely-<userId>.sqlite` per Google account. Same account keeps reminders; a different account opens a different file. Dialog copy was updated. |
| 1.3 | Consent screen (unticked purposes) + `consents` table + Settings toggles | App + DB | **Done** — #40 | Onboarding → consent → auth. Unticked purposes: `cloud_backup`, `anthropic_parse`, `google_speech`. Care-share at Care Link. Settings withdraw. Hosted `consents` migration applied. |
| 1.4 | Local-only mode so reminders work without signing in / cloud | App | **Done** — #38 | “Use without an account” writes `dosely-local.sqlite`. Sync / push / Care Link stay off until Google sign-in; first sign-in can adopt the local file. |
| 1.5 | In-app account deletion + `delete_account` function + wipe local DB + web URL | App + backend | **Done** — #39 | In-app two-step delete, hosted `delete_account` function, local sqlite wipe, `../play-store/delete-account.md`. Play still needs a *public* web URL; the GitHub page is on a private repo. |
| 1.6 | Name the Care Link claimant (name + email); fail closed; longer code; claim throttle | App + DB | **Done** — #34 | 8-digit codes; 10 claims / 15 min; hosted migration applied. |
| 1.7 | Fill `PRIVACY.md` placeholders and link the policy in-app | Docs + app | **Done** — #37, #41 | Placeholders filled. The GitHub blob URL 404s because the repo is private; the app opens a bundled `PRIVACY.md` instead. Play still needs a public web policy URL. |
| 2.1 | Rewrite `PRIVACY.md` for Art. 13 (bases, transfers, retention, rights, Art. 22) | Docs | **Done** — #43 | Legal bases, Singapore/US transfers (no invented SCCs), retention, six rights + withdraw/complain, Art. 22 human review. |
| 2.2 | Stop claiming a `care_alerts` screen and guaranteed FCM-token deletion that the code does not do | Docs or app | **Done** — #43 | Alerts are recorded to avoid duplicates; there is no in-app list. FCM delete on sign-out is best-effort. |
| 2.3 | Disclose timezone, `last_seen_at`, Firebase install id; fix README “on-device” speech | Docs | **Done** — #43 | Timezone / `last_seen_at` / `push_install_id` disclosed. README no longer says speech is on-device. |
| 2.4 | Settings: download my data, delete account, manage consents; contest note on a dose log | App + DB | **Done** — #39, #40, #46 | Download my data (JSON share). Dose logs stay immutable; a correction note is a separate `dose_log_contests` row. Hosted contest migration applied (`--include-all`, after the later prune migration). |
| 2.5 | “Remove this reminder” still only sets `active = false` | App | **Done** — #45 | **Stop reminding me** keeps history. **Delete medicine and history** tombstones locally and `DELETE`s the medicine in Postgres so the family feed drops it. |
| 2.6 | Retention TTLs + prune job (`dose_logs` 24m, `care_alerts` 12m, revoked links 12m, tokens 90d) | Backend | **Done** — #44 | `prune_expired_data()` on hosted `twybepxnqayypzljhcnx`. pg_cron job `prune-expired-data` at 03:20 UTC. Local 24-month dose-log prune on bootstrap. |
| 2.7 | Revoked caregiver must not read `care_alerts`; expire stale claimed links | DB | **Done** — #23, #24 | Caregiver read requires `status = 'active'`. Confirm checks `expires_at`. Lazy auto-revoke of stale `claimed` rows is not implemented. |
| 3.1 | DPIA | Paper | **Done (document)** — `pack/DPIA.md` | Mandatory WP248 assessment. Operator: re-read before Play release. |
| 3.2 | Processor DPAs (Supabase, Anthropic, Google FCM / Sign-In) | Paper | **Partial** — `pack/DPA.md` | Tracker and console links. No DPA has been accepted in a vendor console yet. Speech is a Google controller — no DPA. |
| 3.3 | Document (or eliminate) Singapore + US transfers; TIA / SCCs / DPF | Paper + infra | **Partial** — `pack/TRANSFERS.md` | TIA written. Database still `ap-southeast-1`. SCCs/DPF not executed. Recreating the project in an EU/UK region is still the cleanest fix. |
| 3.4 | Record of processing — `pack/ROPA.md` | Paper | **Done (document)** — `pack/ROPA.md` | Art. 30; small-org exemption does not apply. |
| 3.5 | Breach plan, register, reachable contact; backfill timezone-corruption incident | Paper | **Done (document)** — `pack/BREACH.md` | Register includes B-2026-08-19-A (naive timestamps) and B-2026-08-19-B (fabricated missed doses). Contact: sagnikd91@gmail.com. |
| 3.6 | Decide EEA distribution; Art. 27 representative if yes; privacy contact (no DPO required) | Paper | **Partial** — `pack/SCOPE.md` | EEA/UK distribution is intended. No DPO. Privacy contact is the controller email. Art. 27 representative **not appointed** — required before an EEA Play listing. |
| 3.7 | Separate Washington MHMD consumer health data policy | Docs | **Done (document)** — `MHMD.md` | Names Supabase, Anthropic, Google; second consent before sharing. Still needs a *public* URL (repo is private). |
| 3.8 | Play Data Safety + Health apps declaration + `USE_FULL_SCREEN_INTENT` | Store | **Partial** — `pack/PLAY-DATA-SAFETY.md` | Form answers written to match the policy. `USE_FULL_SCREEN_INTENT` is already in the manifest. Operator must paste into Play Console. Play still needs public policy/deletion URLs. |
| 4.1 | Append-only `phi_access_log` + “who looked” screen | App + DB | **Deferred** | HIPAA track. Also useful for FTC HBNR / MHMD. Start when a B2B deal exists. |
| 4.2 | BAAs (Supabase Team+HIPAA add-on; Anthropic; no BAA for platform speech) | Paper | **Deferred** | |
| 4.3a | Encrypt local medical database | App | **Done** — #33 | sqlite3mc hooks + Keystore, not the EOL `sqlcipher_flutter_libs` package the plan named. |
| 4.3b | Session in Keystore / Keychain | App | **Done** — #29 | |
| 4.3c | Automatic logoff / device-credential re-unlock | App | **Done** — #51 | Device PIN / pattern / biometric after two minutes in the background. No 15-minute session kill. Phones with no screen lock are left usable. |
| 4.3d | Lock-screen names: setting, default private for *care* alerts | App | **Done** — #30, #50 | Patient reminders default private with an opt-in. Care alerts are `NotificationVisibility.private` (foreground and FCM). Deploy `notify-care` for the FCM field to reach devices. |
| 4.3e | Redact OCR (name, address, DoB, Rx) on-device before `parse-medicine` | App | **Done** — #49 | Name, address, DoB, Rx, and prescriber stripped before `parse-medicine`. Medicine name / strength / directions kept. |
| 4.3f | Certificate pinning (network security config exists for no-cleartext) | App | **Todo** (low) | `networkSecurityConfig` already forbids cleartext (#22). Pinning is not done. |
| 4.4 | Written HIPAA policies, MFA on admin accounts, key rotation | Paper | **Deferred** | |

**Counts:** Phases 1 and 2 are closed on `main`. Phase 3 paperwork pack landed on `main` as #48: 3.1 / 3.4 / 3.5 / 3.7 are documents; 3.2 / 3.3 / 3.6 / 3.8 wait on operator actions (sign DPAs, region or SCCs, Art. 27 representative, Play Console paste). 4.3a–e are closed on this branch. Remaining application work is 4.3f (pinning, low). HIPAA 4.1–4.2 and 4.4 deferred.

### Remaining work, in order

1. **Phase 1 blockers:** closed (#22, #33, #34, #37–#41). Overlay-install on the Galaxy M33 still pending.
2. **Phase 2 honesty:** closed on `main` (#47). Optional leftover from 2.7: auto-revoke stale `claimed` links.
3. **Phase 3 operator leftover:** accept DPAs in vendor consoles; decide EU-region vs SCC paperwork; appoint Art. 27 representative (or delay EEA listing); paste Play Data Safety; host public policy/deletion/MHMD URLs. Documents are on `main` (#48).
4. **Phase 4 leftovers on this branch:** 4.3f certificate pinning (low; needs backup pins and a rotation plan — Let's Encrypt leaf pins will break the app).
5. **When a B2B/HIPAA deal exists:** 4.1 access log, 4.2 BAAs, 4.4 written Security Rule policies.
