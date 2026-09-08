# Medicyn — Core Feature Status

A snapshot of what's built versus what's pending, pulled from `MEDICYN.md`'s
"Core features" section. See that file for the full source of truth,
architecture decisions, and pending items beyond features.

---

## Fully done

- **F1 — Photo-label + voice dosage AI confirmation.** `capture_ocr`,
  `voice_capture`, `review_edit` + the `parse-medicine` edge function.
- **F2 — Pharmacy-agnostic tracking.** No retailer dependency anywhere in
  the codebase.
- **F3 — Offline-first reliability.** On-device exact alarms; DST-drift fix
  in #68.
- **F4 — Family sharing + missed-dose alerts.** 1:1 only —
  `CareService.currentLink()` returns a single link.

## Partially done

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

## Not built at all

- **F5 — Drug-drug interaction warnings.** Decision: Claude reasoning over
  the medicine list, not a licensed clinical database. Every flag ships
  with "AI-generated screening, not a clinical database — confirm with your
  pharmacist." Incremental trigger (new/changed medicine vs. active list
  only). Its own visible push, never folded into silent sync. Never names a
  drug in a notification payload.
- **F9 — Family plan pricing on care links.** Needs multi-link schema,
  which the 1:1 lock forbids today.
- **F10 — Premium caregiver dashboard.** Foundation only.
- **F11 — "Ask about my meds" assistant.** Same Claude pipe, new prompt.

## Accepted, not started

Selected from a healthcare-gap review (September 2026). Scope rule: only
ideas that fall out of data Medicyn already holds, or point the existing
camera at different paper.

- **N1 — Refill basket.** Collapse per-medicine warnings into one list on
  one date a month. Plugs into `refill.dart`, `Medicines.tabletsRemaining`;
  no schema change needed. Not unit-aware — still a raw tablet count, so it
  won't sensibly cover ml, puffs, drops, or injections if one of those is
  ever added as a dose unit.
- **N2 — Tests that are due.** The monitoring a regimen implies
  (levothyroxine → TSH, warfarin → INR, metformin → HbA1c, statin → lipids
  + LFT). Plugs into `insights_screen.dart`, `TodayCareReminders`.
- **N3 — Emergency card.** Medicines, doses, allergies, conditions, blood
  group, caregiver's number. Plugs into `data_export_service.dart`,
  Profile.
- **N4 — Discharge summary translator.** Photograph a discharge summary →
  plain language, every medicine created with times, red flags, follow-up
  date. Reuses the OCR → `parse-medicine` → review-and-confirm pipeline.

**Before N1/N2/N4 can start:**
- `Medicines.tabletsRemaining` is nullable/opt-in — N1's basket is empty
  for anyone who never counted tablets. Candidate: read quantity off the
  label at review time.
- Extend `redactPharmacyLabel()` for discharge documents (name, hospital,
  MRN, diagnosis, treating doctor) before any N4 work.
- N2's drug→test map should be a static table, not a Claude call.
- N2 must ask once for treatment start date and store it —
  `Medicines.createdAt` is when it was added to Medicyn, not when the
  doctor started it.
- N3 must not be a lock-screen surface — one tap from Profile, plus a
  printable copy.
- N4 needs list-shaped extraction (current `sanitiseExtraction()` /
  `ParsedMedicine` assume one medicine), a multi-item review screen, and a
  re-weighted quota (`parse-medicine/quota.ts`).

**Not scheduled at all:** eight further ideas were reviewed as good fits
but aren't scheduled — same-salt generic pricing, "how to take this"
cards, batch-recall alerts, an Ayush/allopathy interaction check, a
records drawer, a misinformation check against the person's own
medicines, hospital-bill checking, and extending the dose engine to
non-pill daily tasks.
