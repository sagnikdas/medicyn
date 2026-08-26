# Dosely — All Features at a Glance

Every feature from the dosely feature & positioning brief in one table — tier, status as of 2026-08-24, and the one-line angle — followed by a full description of each.

| # | Feature | Tier | Status | One-line angle |
|---|---------|------|--------|----------------|
| F1 | Photo-label + voice dosage AI confirmation | Tier 1 — wedge | Built | The only app that actually understands your prescription. |
| F2 | Pharmacy-agnostic tracking | Tier 1 — wedge | Built | Works with any pharmacy — not locked to one. |
| F3 | Offline-first reliability | Tier 1 — wedge | Built | Reminders that fire even with zero signal. |
| F4 | Family/caregiver sharing + missed-dose alerts | Tier 2 — trust | Built (1:1) | Know the moment a dose is missed — wherever you are. |
| F5 | Drug-drug interaction warnings | Tier 2 — trust | Not built | A safety net, built in. |
| F6 | Doctor-ready adherence export | Tier 2 — trust | Partial | Walk into every appointment with the full picture. |
| F7 | Virtual caregiver dashboard | Tier 3 — premium | Partial | Everything Hero's hardware does — without the hardware. |
| F8 | Refill reminders → pharmacy referral | Monetization #1 | Half built | Runs-out warning shipped; the reorder/affiliate action is the missing revenue hook. |
| F9 | Family plan pricing on care links | Monetization #2 | Not built | First link free, extra members $2–3/mo — needs multi-link schema + paywall. |
| F10 | Premium caregiver dashboard | Monetization #3 | Foundation built | The "virtual Hero" tier at ~$7–10/mo. |
| F11 | "Ask about my meds" AI assistant | Monetization #4 | Not built | Q&A grounded in the person's actual med list — same Claude pipe, new prompt. |
| F12 | Medicare RTM billing (US, B2B) | Monetization #5 | Not started | $5–15/patient/month via RTM partners — highest per-user ceiling, partnership-led. |
| F13 | Pharma data licensing | Monetization #6 | Not started | Deliberately deferred — needs ~100K+ users and clashes with the privacy stance today. |

---

## F1 — Photo-label + voice dosage AI confirmation

Dosely's core capture workflow — four steps that replace manual form-filling entirely. The user photographs the prescription label (read on-device with ML Kit OCR; the photo is discarded immediately), then says the dosage out loud ("one tablet twice a day, morning and night"), which captures real-world usage even when it doesn't exactly match the printed label. The OCR text and voice transcript are sent to a Supabase Edge Function where Claude structures them into drug name, strength, dose, frequency, and times. The app shows back its interpretation in an editable review form; nothing is saved until the user confirms.

Every other reminder app in the researched competitor set — Medisafe, MyTherapy, Dosecast, even hardware players like Hero — requires manually typing the medication name, dosage, and schedule into a form. None combine AI label-reading with voice-based dosage confirmation in one flow. This removes the single biggest friction point (manual data entry) in every competing app, which matters most for elderly users who struggle with small-form-factor typing.

**Status detail:** Built and shipped — `capture_ocr`, `voice_capture`, and `review_edit` modules plus the Claude edge function form the working core loop.

## F2 — Pharmacy-agnostic tracking

Dosely tracks medications no matter which pharmacy filled the prescription — CVS, Walgreens, an independent local pharmacy, a mail-order service, or one in another country. Because capture happens via a photo of the label rather than pulling from a pharmacy's order system, the app has no dependency on any retailer's infrastructure.

This directly counters how the "free" retail competitors are built: Amazon Pharmacy (PillPack), CVS MedRemind, and Walgreens reminders are bundled into each retailer's own pharmacy service and can only track medications *they* filled. A caregiver managing an elderly parent's medications — often split across two or three pharmacies plus over-the-counter supplements — gets one complete list in dosely instead of three fragmented apps. It turns the retail giants' biggest structural advantage (owning the pharmacy) into their biggest limitation.

**Status detail:** Built — true by design; there is no pharmacy-system dependency anywhere in the codebase.

## F3 — Offline-first reliability

Reminders don't depend on an internet connection to fire. Scheduling, storage, and alert-triggering all happen locally on the device: once a medication is set up, an exact alarm is scheduled directly on the phone (Drift SQLite is the source of truth), so the reminder fires with no connectivity and no live app process. Cloud sync to Supabase exists for backup and multi-device, but firing never waits on it.

This matters for rural and low-connectivity homes, for connections that drop at exactly the wrong moment, and especially for the India market where day-to-day connectivity is less reliable. It's also a trust argument: a medication reminder that occasionally fails on a network hiccup creates false confidence that the system is watching when it isn't. No researched competitor leads with this claim. One precision note for marketing copy: offline covers the reminder-firing mechanic — relaying a missed-dose alert to a remote caregiver still needs connectivity.

**Status detail:** Built — on-device exact alarms with Drift as source of truth; a DST-drift fix landed in PR #68 (merged).

## F4 — Family/caregiver sharing + missed-dose alerts

Lets a family member or caregiver who isn't in the same house see and manage an elderly person's medication schedule. When a dose is confirmed, the caregiver sees it in a dose feed; when a scheduled dose passes unconfirmed, the system escalates — a visible push notification ("Amma missed a dose") goes to the caregiver's phone rather than just re-alerting the person who already missed it. Caregivers can also edit the patient's schedules remotely, with a silent push re-arming the patient's alarms.

This is the feature Medisafe calls "Medfriend," a proven driver of premium upgrades — people pay for *knowing* rather than *hoping* a parent took their medication. It's also the exact capability CareZone lacked even at $150M in funding and 3.5M users.

**Status detail:** Built, but 1:1 only — care links, the `notify-care` FCM edge function, dose feed, and caregiver editing are all shipped; `CareService.currentLink()` returns a single link, so multiple caregivers per patient (or one caregiver covering two parents) isn't supported yet. PRs #68/#69 (merged) hardened the missed-dose blind spot and sync races.

## F5 — Drug-drug interaction warnings

Safety alerts that fire when two or more medications on a person's list can negatively affect each other — reducing effectiveness, dangerously amplifying an effect, or causing a side effect neither drug causes alone. Classic examples: warfarin + aspirin (compounding bleeding risk), statins + certain antibiotics (muscle damage), ACE inhibitors + potassium supplements (arrhythmia risk), sedatives + other sedatives (suppressed breathing).

In dosely, every newly added medication is checked against the person's existing list by sending the drug names directly to Claude — the same model already used for label parsing — and asking it to identify known interactions, rather than integrating a licensed clinical database. That path was evaluated and dropped: NIH's own free interaction API was discontinued in 2024, and every alternative that was checked (DrugBank, Micromedex, Lexicomp, and the smaller free academic options) turned out to be either enterprise-priced or licensed for non-commercial use only. The tradeoff is real — a database gives a citable, versioned answer; a model's reasoning does not — so every flag ships with an explicit "AI-generated screening, not a clinical database" disclosure rather than being presented as authoritative. A conflict produces a flag like "⚠️ This may interact with your blood thinner — check with your pharmacist." Elderly users are disproportionately on 5+ concurrent medications ("polypharmacy") — exactly when interaction risk climbs and when a remote caregiver can't catch it manually.

**Status detail:** Not built — no interaction-checking code anywhere in the repo. Full build plan in `DRUG-INTERACTIONS.md`.

## F6 — Doctor-ready adherence export

A one-tap export of the full medication picture — the medication list with dosages and start dates, adherence rate over time (per medication), and the missed-dose *pattern* (e.g. consistently missing the evening dose, which is diagnostically useful) — formatted as a clean PDF a doctor or pharmacist can review in seconds. The value isn't the report; it's removing a recurring pain point: a caregiver being asked "how has adherence been?" at an appointment with only a vague memory to answer from.

Dosely already has every data point as a byproduct of the core confirmation loop, so this is purely a presentation/export layer. Medisafe and MyTherapy both ship it — table stakes rather than a wedge, but near-free to add.

**Status detail:** Partial — a GDPR Art. 15/20 "Download my data" JSON export, an Insights screen with weekly adherence, and per-schedule dose history all exist; the doctor-facing PDF report does not.

## F7 — Virtual caregiver dashboard

A screen the adult child or caregiver uses on their own phone to remotely see and manage the patient's medication status: adherence at a glance, real-time missed-dose alerts, the full medication and refill picture, trend history to catch a slipping pattern early, multi-person management (both aging parents in one view), and remote actions (nudge a reminder, edit a schedule, call them directly).

Hero's $30–60/month hardware sells this same caregiver-visibility outcome — the dispenser is just the data source; the product a family pays for is the dashboard that says "your parent is on track" without a phone call. Dosely generates the equivalent signal in software via the confirmation loop, so the dashboard delivers the same peace of mind without the device cost.

**Status detail:** Partial — the caregiver already gets a dose feed, patient-reminders view/editing, phone dial, device-health panel, and change history; missing are caregiver-side trends, the multi-person view, and a weekly digest.

## F8 — Refill reminders → pharmacy referral

The consumer half is shipped: `refill.dart` computes days-of-supply per schedule from remaining stock and the schedule's daily dose rate, warning five days before the bottle runs out ("long enough to get to a pharmacy; a last-tablet warning arrives after it could have helped"). The monetization half is the missing piece: a one-tap reorder action on that warning — GoodRx-style discount links in the US (commission per fill), 1mg/PharmEasy affiliate links in India. The user experiences it as a favor, not an ad.

This is the highest-priority monetization item because it's the only model the India research showed actually works there (anchor revenue to a transaction, not a subscription), it works in both markets, and affiliate links are a weekend of work on top of code that already exists.

**Status detail:** Half built — refill tracking and the 5-day warning shipped in PR #56 and were refined in PR #69 (merged; stock-derivation tests); no reorder/referral action or affiliate integration exists yet.

## F9 — Family plan pricing on care links

The pricing model that turns the existing care-link infrastructure into recurring revenue: the first care link stays free — it's the growth loop, since every parent onboards a caregiver and every caregiver is a new user — while additional linked people cost $2–3/month (Dosecast's proven per-member model). A family where siblings split responsibility for a parent, or one child manages both parents, becomes the paying tier.

**Status detail:** Not built — there is no payments or paywall code anywhere in the repo, and since care links are currently 1:1, the multi-link schema (F4's limitation) has to come first.

## F10 — Premium caregiver dashboard

The paid tier built on F7's foundation: longer-horizon adherence trends, the multi-person view, a weekly email digest ("Mom: 96% this week"), and missed-dose pattern insights — priced at ~$7–10/month. That's above the $4.99/month software norm (Medisafe's validated ceiling) but justified by pricing against Hero's $29.99–59.99/month hardware subscription instead: same caregiver-visibility outcome at 4–6× less.

**Status detail:** Foundation built — dose feed, caregiver editing, device-health panel, and change history are shipped; the trends, digest, multi-person view, and the premium gate itself are not.

## F11 — "Ask about my meds" AI assistant

A Q&A surface grounded in the person's actual medication list: "What is this medicine for?", "Can I take it with food?", "What happens if I missed a dose?" — genuinely valuable for elderly users who would otherwise call a family member or guess. The Claude pipe already exists in the parse edge function; this is the same infrastructure with a new prompt and a chat surface, making it one of the cheapest premium-gated features to build.

It needs careful "not medical advice — ask your pharmacist" framing, but Medisafe ships equivalent educational content, so the compliance path is well-trodden.

**Status detail:** Not built — the Claude edge function is parse-only today (label + transcript → structured fields); no Q&A surface exists.

## F12 — Medicare RTM billing (US, B2B)

The highest revenue-per-user path in the analysis. Remote Therapeutic Monitoring CPT codes let US providers bill Medicare for monitoring services delivered through software like dosely: ~$20 one-time setup (98975), ~$45–55/month device/software supply requiring readings 16+ of every 30 days — which dosely's daily confirmations easily satisfy (98976/98977), and ~$50–90/month treatment management time (98980/98981). A provider bills roughly $100–150/patient/month fully utilized; dosely's cut as the software vendor is typically $5–15/patient/month. Math: 1,000 enrolled patients ≈ $60–180K ARR; 10,000 ≈ $600K–1.8M ARR.

Dosely never bills Medicare directly — the model is licensing to home-health agencies or an RTM aggregator (Hero's model via Assure Health). Requirements: FDA "medical device" definition review (low-risk adherence software generally needs no clearance), HIPAA BAAs, and one caveat — current RTM device-supply codes are body-system-specific with no dedicated medication-adherence code yet, which is exactly why partnering beats going direct. The service is billable almost immediately: one signed partner with 50 consented patients is a real pilot.

**Status detail:** Not started — no B2B/provider-facing surface exists in the codebase, though the underlying dose-log data it would monetize is already being collected.

## F13 — Pharma data licensing

Medisafe's second (and likely larger) revenue line: licensing de-identified, cohort-level adherence and behavioral data to pharmaceutical companies — Medisafe claims 25+ pharma partners against its 13M-patient base. Real money, but only at scale: pharma buyers need ~100K+ active users with meaningful per-condition cohorts before the data has any value, plus HIPAA de-identification and upfront consent language.

Deliberately deferred for dosely — and possibly skipped permanently. The current consent/privacy architecture (GDPR export, consent service, "the photo is discarded immediately") is a trust asset with elderly users and caregivers that clumsy data-selling would burn. If ever pursued, it must be transparent and optional.

**Status detail:** Not started — by design; the privacy architecture currently points the opposite direction.
