# 3.1 — Data Protection Impact Assessment

**Controller:** Sagnik Das.
**Processing:** Medicyn Android app (`com.sagnikdas.medicyn`) and its backend.
**Date:** 20 August 2026.
**Version:** 1. Against `main` @ `f73aed5`.
**Next review:** before Play release, and whenever a data flow is added.

This is the DPIA GDPR Art. 35 and EDPB WP248 require. It is written from the
code and from `PLAN.md`'s Known gaps, not from a template that pretends the
risks are generic.

## 1. Why a DPIA is mandatory

WP248: a DPIA is required when processing is likely high risk, especially
when two or more of its nine criteria apply. Medicyn hits **five**:

1. **Special category data** — medicines, schedules, dose history (Art. 9 health).
2. **Vulnerable data subjects** — the design target is elderly parents.
3. **Disclosure to a third party with write access** — one linked family
   member can read *and* edit medicines.
4. **Innovative use of technology** — an LLM structures health data from OCR
   and speech text.
5. **Risk of physical harm** — a missed or false missed-dose alert can change
   whether someone is checked on, or whether they take a medicine.

A DPIA would be required on (1) and (5) alone. The others make it heavier.

## 2. Description of processing

### What Medicyn is

A medication reminder. The person who takes the medicine is the data
subject. One other person may be linked, with that subject's confirmation,
to see and edit the same record and to receive a notification if a dose is
unanswered for more than 30 minutes.

### The four flows

| Flow | What moves | Where | Legal basis (Art. 6 + 9) | Consent flag |
|---|---|---|---|---|
| On-device reminders | Medicines, schedules, dose logs, contest notes | Encrypted SQLite on the phone | 6(1)(b) + 9(2)(a) | Consent screen (health data) |
| Cloud backup | Same rows | Supabase `ap-southeast-1` (Singapore) | 6(1)(a) + 9(2)(a) | `cloud_backup`, off unless ticked |
| AI fill-in | OCR text + transcript, up to 4,000 characters | Anthropic, United States | 6(1)(a) + 9(2)(a) | `anthropic_parse`, off unless ticked |
| Family share | Medicines, schedules, dose history, timezone; FCM body for missed doses | The linked account; Google FCM in the US | 6(1)(a) + 9(2)(a) | `care_share` at Care Link |

Two more, not in that four but in scope:

- **Google Sign-In** — email, name, Google account id. Art. 6(1)(b). Optional;
  local-only mode exists.
- **Google speech** — raw audio leaves the device on most Android phones.
  Google is a **controller** of that audio. Art. 6(1)(a) + 9(2)(a).
  `google_speech`, off unless ticked.

### Recipients

Supabase (processor), Anthropic (processor, if the DPA is executed), Google
FCM (processor for delivery), Google speech (controller), Google Sign-In /
Play (independent controllers). No advertisers. No analytics SDK.

### Retention

Account, medicines, schedules: while the account exists, or until that
medicine is deleted. Dose logs: 24 months rolling. Care alerts: 12 months.
Revoked care links: 12 months. Device tokens: 90 days idle. Enforced by
`prune_expired_data()` and a local prune.

### What we do *not* do

No GPS. No advertising identifiers. No EHR. No billing. No sale of data.
Label photos are OCR'd on-device and deleted. Claude does not decide
anything — every field is reviewed before Save (not Art. 22).

## 3. Necessity and proportionality

**On-device storage** is necessary for the reminder to fire without a
network. Encrypted SQLite + Keystore is the current control.

**Cloud backup** is not necessary for the reminder. It is a separate,
unticked consent so losing a phone does not lose the history. That is
proportionate if, and only if, the consent stays unticked by default
(it does).

**Sending the full OCR blob to Anthropic** is *not* the minimum necessary.
A pharmacy label routinely carries name, address, date of birth, prescriber
and Rx number. Only drug name, strength, form, dose and times are needed.
Phase 4.3e (on-device redaction) is the remaining control. Until it ships,
Anthropic consent must stay off-by-default, which it is, and the DPIA
records residual risk.

**Cloud speech as the default recogniser** is not necessary. `onDevice: true`
exists and fails on phones with no offline model. The app asks consent and
defaults off. That is the current control. Switching the default to on-device
with typed fallback would be better; it is not done.

**Caregiver write access** is a product choice, not a legal necessity. A
read-only mode would shrink the coercive-caregiver risk. There is no
read-only mode. Consent is named, confirmed by the patient, and withdrawable
(withdrawing `care_share` tries to revoke the live link). Residual risk
stays.

**Six-digit / eight-digit codes read over the phone** — an 80-year-old
reading a code aloud is a weak Art. 9 consent ceremony if they do not
understand who will see their medicines. The code is now 8 digits, claiming
is throttled, and the patient must confirm the claimant **by name**. That is
the current control. It is still possible to confirm the wrong person.

## 4. Risks to people

Likelihood × severity below is qualitative. "High" means this is why the
DPIA exists.

### R1 — False alarm (fabricated missed dose)

A sweep that treated a new reminder as if it had always existed invented
missed doses. Nine of eleven live missed-dose rows were created that way.
Once push exists, that is a notification telling a family member their
parent stopped taking medication.

**Control:** `MissedDoseDetector.wasArmed` bounds occurrences on
`schedules.updatedAt`. Silence beats a false alarm. Residual: editing a
reminder forfeits unrecorded backfill from before the edit.

**Residual:** Medium. The bug is closed; the class of error (the sweep
disagreeing with what was actually armed) is still the dangerous one.

### R2 — False reassurance ("no alerts" read as "all is well")

Missed doses are only detected while the parent's app is in the foreground.
A parent who does not open the app for two days generates no missed doses
and no alerts. A caregiver who treats silence as adherence is misled.

**Control:** None in product copy today beyond this DPIA and `PLAN.md`.
There is no silent-device detection yet. `PRIVACY.md` does not tell the
caregiver this.

**Residual:** High — this is the residual that Phase 3 cannot code away
and that a later silent-device job should close.

### R3 — Wrong times shown to the family (timezone corruption)

Client-stamped timestamps were written without a UTC offset. Postgres read
them as UTC. The *other* side of a care link was shown times no alarm ever
rang at. Integrity of health data, Art. 4(12) accidental alteration.

**Control:** `SyncService.isoUtc`; hosted correction migration
`20260819120000_fix_naive_client_timestamps.sql`. See [BREACH.md](BREACH.md)
B-2026-08-19-A.

**Residual:** Low if every device is on a post-fix build. A pre-fix client
would re-corrupt.

### R4 — Coercive caregiver with write access

The linked person can add and edit medicines. There is no read-only link.
A controlling relative can change a schedule or hide a medicine.

**Control:** Patient confirms the claimant by name; either side can
disconnect; withdrawing `care_share` tries to revoke the live link; one
link per person.

**Residual:** High for the people this app is for. A read-only mode is the
missing control.

### R5 — Special-category data at Anthropic without redaction

Up to 4,000 characters of raw label text, including identifiers the OCR
did not need.

**Control:** Unticked consent; photo never uploaded; human review before
save. Redaction (4.3e) is not done.

**Residual:** High for anyone who ticks AI fill-in, until 4.3e ships.

### R6 — Google as controller of voice audio

The platform speech recogniser typically sends audio to Google. No DPA
covers it. No BAA is available.

**Control:** Unticked `google_speech` consent. `PRIVACY.md` says the audio
leaves the device.

**Residual:** Medium. The honest residual is "do not tick voice input if
you do not want Google to hear a medication description."

### R7 — Transfers with no adequacy (Singapore + US)

All three recipients of health data that leaves the phone are outside the
EEA/UK. Singapore has no adequacy decision. Paperwork in
[TRANSFERS.md](TRANSFERS.md) and [DPA.md](DPA.md) is the control; it is
not yet executed in consoles.

**Residual:** High until DPAs/SCCs/DPF are actually accepted, or the
Supabase project is recreated in an EU/UK region.

### R8 — Informed consent from an elderly user

Long policy, several toggles, a code read over the phone. Art. 7 and Art. 9
need a freely given, specific, informed indication.

**Control:** Unticked purposes; separate sentences hashed into `consents`;
Care Link names the claimant; local-only mode so backup is not a condition
of using reminders (Art. 7(4)).

**Residual:** Medium. The ceremony is better than a single "I agree"
checkbox. It is still a lot to ask of the design target.

### R9 — Caregiver write + no "who looked" log

When a caregiver reads the dose feed, nothing records that it happened.
FTC HBNR and a future HIPAA deal both want this. Out of Phase 3 scope
(4.1).

**Residual:** Medium for detection of misuse; accepted until 4.1.

## 5. Measures (what is already in the product)

- RLS through `can_access_user_data()`, adversarial SQL tests.
- Care-link state only via RPCs; 8-digit codes; claim throttle; named
  confirm.
- Encrypted per-account local DB; session in Keystore; Android backup off.
- Consent capture and Settings withdraw; local-only mode.
- Account deletion in-app and via email / `../../play-store/delete-account.md`.
- Download my data; contest note on a dose log; true delete of a medicine.
- Retention prune; in-app privacy policy.
- Notification content composed server-side.
- `notify-care` re-verifies the JWT.

## 6. Go / no-go

**Processing may continue** for on-device reminders, for backup / parse /
speech / share *when the matching consent is ticked*, and for Play
preparation, provided:

1. Operator completes [DPA.md](DPA.md) acceptances before any EEA/UK user
   is invited.
2. An Art. 27 representative is appointed before an EEA Play listing
   ([SCOPE.md](SCOPE.md)).
3. 4.3e (OCR redaction) is treated as the next *code* control, not as
   optional polish.
4. Product copy never tells a caregiver that silence means adherence (R2).
5. This DPIA is revised if a fifth flow appears (analytics, a second
   caregiver, EHR).

Consultation of data subjects: not done as a formal survey. The design
target (elderly parent, one family helper) is the source of the residual
risks above. A supervisory authority prior consultation (Art. 36) is not
sought: residual risk is high in places, but the measures in §5 are the
ones WP248 expects a small controller to take, and the un-ticked consents
are the main brake.

Signed (controller): Sagnik Das, 20 August 2026.
