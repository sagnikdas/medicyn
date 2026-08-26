# Dosely — F5: Drug-drug interaction warnings

The plan for turning F5 in `dosely-features-summary.md` ("Not built — no
interaction-checking code anywhere in the repo") into a shipped feature.
Written after a feasibility pass that changed the design from what the
features summary originally assumed — see the Appendix for what was tested
and why the original approach was dropped.

**Last updated:** 2026-08-25 · Scoping only, no code written yet.

---

## The decision this plan is built on

The features summary assumed "RxNorm paired with an interaction-checking API
such as DrugBank." That path is closed: NIH discontinued its own free
interaction API in January 2024, DrugBank/Micromedex/Lexicomp are
enterprise-priced ($10K–$250K+/year, sales-quote-only), and the one credible
free option — DDInter 2.0, a peer-reviewed, self-hostable database — is
licensed **CC BY-NC-SA 4.0, NonCommercial**. Dosely is a commercial product
even on its free tier, so shipping DDInter's data in the app isn't licensed
as-is (see Appendix for the actual terms text and what was tested against it).

**The plan instead sends the patient's medicine list to Claude directly and
asks it to identify known interactions**, using the same edge-function
pattern already proven three times in this codebase (`parse-medicine`,
`notify-care`, `delete_account`). This sidesteps the licensing problem
entirely — Anthropic's API is already paid for and commercially licensed —
and, in testing, resolved Indian brand names (Dolo 650, Crocin Advance) and
caught at least one interaction DDInter's own dataset was missing
(Lisinopril + Spironolactone) with no extra normalization step. What it gives
up is a citable, versioned source: the severity comes from the model's
reasoning, not a dataset, so it is not deterministic and cannot be pointed to
if someone asks "why did the app say this." The mitigation for that gap is
not more engineering — it's one disclosure line, and it's not optional.

## Locked decisions

| Decision | Choice |
|---|---|
| Source of truth | Claude (`claude-haiku-4-5`) reasoning over the medicine list — not a licensed clinical database |
| Disclosure | Every flag ships with "AI-generated screening, not a clinical database — confirm with your pharmacist." Not a polish item; ships with Phase 1 or Phase 1 doesn't ship. |
| Trigger | Incremental — only the new/changed medicine is checked against the rest of the active list, not a full recheck on every edit |
| Push urgency | An interaction flag gets its own visible push event, not folded into the silent `data_changed` sync channel — treated like `missed_dose`, not like a routine edit |
| Notification content | Never names the drugs in the push payload itself — same rule `refill_low` already established (a lock-screen alert that quoted a drug recreates the exposure it was built to avoid) |
| Data source for tuning | No external database in production. A curated regression list (Appendix) stands in for ground truth, grown from real dismissed/missed cases over time |

## Where it stands

Not started. This document exists because of a feasibility pass, not
because any of this is built:

- DDInter 2.0's bulk CSV was downloaded and tested against a fixed combo
  list — real findings in the Appendix, none of it usable in the shipped app
  under its current license.
- One commercial wrapper (RxLabelGuard) was checked for data provenance, not
  tested live — no account was created.
- The Claude-only approach was reasoned through against the same combo list
  as a feasibility check, not tested against the live API (no
  `ANTHROPIC_API_KEY` was available in the environment this was scoped in).
  **Phase 1's first real task is confirming the live model reproduces this.**

---

## Phase 1 — Claude-based interaction check, patient-only, local

- [ ] **Consent — sentence and surfacing.** New `ConsentPurpose.interactionCheck`
      in `consent_purpose.dart`, its own hashed sentence under
      `kConsentPolicyVersion`, distinct from `anthropicParse`: the whole
      standing medicine list on an ongoing basis, not one label + transcript
      once — worded to already cover a linked caregiver seeing the result,
      so Phase 2 doesn't force a re-consent event later. **Not** in
      `ConsentPurpose.firstScreen` — that list is the three things every
      user hits in the core capture loop on day one (`cloudBackup`,
      `anthropicParse`, `googleSpeech`); interaction checking is downstream
      and, like `careShare`, only becomes relevant once it actually applies.
      Prompt for it contextually — the first time a second medicine exists
      to make a check possible — not at first launch for someone who may
      only ever track one prescription.
- [ ] **Edge function — parameters and quota.** `check-interaction` reuses
      `caller.ts` verbatim; forced tool-use call to `claude-haiku-4-5` at
      `temperature: 0` (reduces variance, does not guarantee identical
      output across model versions — Phase 3's drift detection exists
      because of that gap, not despite it). New `check_interaction_usage`
      ledger, same shape as `quota.ts`. Proposed cap: **30/day** — looser
      than `parse-medicine`'s 40 would suggest is needed, since bulk-add
      batching means even a large one-sitting import is a single call, so
      normal usage is a handful of edits a week, not a day. The cap is a
      sanity fuse against a buggy retry loop or deliberate abuse, not a
      real cost control — even sustained daily abuse at this cap costs
      cents, per the earlier cost breakdown.
- [ ] **Tool schema — no `Unknown` severity value.** Returns
      `{ drugA, drugB, severity (Major/Moderate/Minor), confidence, reason }[]`
      — deliberately no `"Unknown"` tier. System prompt instructs: omit a
      pair rather than guess when unsure, full stop — a missed pair the user
      can still raise with their pharmacist is safer than a wrong one stated
      as fact. This is a direct reaction to what feasibility testing found
      in DDInter's own data: an `"Unknown"` severity (Diazepam+Alprazolam)
      that showed up as a flag but told the user nothing actionable. Better
      to not flag at all than flag without a usable answer.
- [ ] **`InteractionFlags` Drift table — canonical pairing.** Columns:
      `medicineIdA`, `medicineIdB`, `severity`, `reason`, `source`
      (`"claude_reasoning"`), `modelVersion`, `checkedAt`, `acknowledged`,
      `updatedBy`, `pendingSync`. **Unsynced in this phase** — local-only
      while the feature is unproven, same reasoning as every other
      "smallest safe slice first" feature in this codebase. A pair needs a
      canonical order (e.g. `medicineIdA` = the lexicographically smaller
      id) and an upsert-on-conflict write, not a plain insert — without
      that, re-editing either medicine later re-triggers a check on the
      same pair and silently accumulates duplicate rows instead of updating
      the existing one.
- [ ] Trigger: adding or editing a medicine calls `check-interaction` with
      that drug plus the rest of the active list; result cached, never
      re-asked on every screen render.
- [ ] Bulk-add batching: detect several medicines being added in one session
      (the initial capture/import flow is the obvious case) and send them as
      a single `check-interaction` call covering the whole new set, instead
      of firing the incremental per-edit trigger once per medicine. Without
      this, a large one-sitting entry (worst case ~100 medicines) fires one
      call per medicine, can silently exhaust the daily quota partway
      through onboarding — the remaining medicines then save with no check
      at all — and, once Phase 2 ships, floods the caregiver with a burst of
      pushes. No new capability needed for this: `check-interaction` already
      takes a list, since Claude reasons over the whole set in one pass
      rather than pairwise; this is a trigger-logic distinction (one edit vs.
      many in a session), not a new endpoint.
- [ ] **Severity-tier template.** Pure string substitution against the
      `severity` returned, no LLM call for this part, carrying the
      mandatory disclosure line from earlier. Lives as its own small module
      (not inline in the widget) so Phase 3's threshold tuning can change
      display rules without touching the edge function or the banner
      widget.
- [ ] **Fail-closed — a distinct state, not just an absent one.** Edge
      function unreachable → banner shows "not checked," visually distinct
      from any severity color (grey/neutral, not a weaker version of the
      Minor styling) so it can't be misread as "checked, nothing found."
      Retried automatically the next time the affected medicine's screen is
      opened or the app is foregrounded — not left stuck until the user
      happens to edit that medicine again, which could be months.
- [ ] **Manual verification — this seeds the Phase 3 regression file.** Run
      on the test phone against the same combo list used in feasibility
      testing (Warfarin+Aspirin, Atorvastatin/Simvastatin+Clarithromycin,
      Lisinopril+Spironolactone, Diazepam+Alprazolam, Dolo 650+Warfarin,
      Crocin Advance+Warfarin), plus the negative-control combos from
      Phase 3. First point any of this touches the real API — and its
      results become `regression_cases.json`'s seed data directly, not a
      separate exercise repeated later.

## Phase 2 — Caregiver visibility

- [ ] **Sync — schema and write ordering.** `user_id` stored directly on the
      `interaction_flags` row, not derived through a join to `medicines` —
      a flag stays readable as history even if one of its two medicines is
      later deleted, same as `DoseLogs` outliving an inactive schedule. RLS
      is a one-liner reusing the existing `can_access_user_data(user_id)`
      function already applied to `medicines`/`schedules`/`dose_logs` — no
      new access-control design. **Ordering matters**: the device that ran
      `check-interaction` must push the row to Supabase and confirm the
      write succeeded *before* calling `notify-care` — not fire the push
      optimistically the moment the local call returns. Same pattern
      `missed_dose` already documents (push the data, then notify); skipping
      it here reopens the class of race the sync fixes in #68/#69 closed —
      a caregiver taps a push and the row isn't there yet.
- [ ] **Push payload and dedup.** New event `interaction_flagged` in
      `push_events.dart` (mirrored in `notify-care/index.ts`), carrying
      `event`, `patientId`, and a `flagId` so tapping it deep-links to that
      flag — same shape as `missed_dose`'s existing keys. The patient's
      *name* is fine in the lock-screen text (`missed_dose`'s own precedent
      is "Amma missed a dose") — only the drug identity is the exposure
      risk `refill_low` was built to avoid, not the fact that a check
      happened. One `check-interaction` call returning multiple flags is
      **one push, not one per flag** — "possible interactions flagged,"
      opening to a list.
- [ ] **Bidirectional, and not actually a new problem.** Whichever side's
      edit triggered the flag, the *other* side gets `interaction_flagged`
      — a safety flag shouldn't wait for someone to happen to open the app
      the way a routine `data_changed` edit does. The calling device
      doesn't need to know *who* to notify, only *that* it should —
      `notify-care`/`authorize.ts` already resolves the linked counterpart
      via care-link membership for every existing event type; this inherits
      that unchanged.
- [ ] **Acknowledgment.** `acknowledged` + `acknowledgedBy` syncs
      last-write-wins on `updatedAt`, same as `Medicines`/`Schedules` — a
      single idempotent boolean, genuinely lower-risk than the sync races
      fixed in #68/#69, not a new hard problem. Display reuses the existing
      edit-attribution convention (`updatedBy` already shows who changed
      what, per `PLAN.md`'s conflict-safety design). Dependency on Phase 3:
      its "acknowledge invalidation" (a flag re-surfacing when the
      underlying medicine's dose/schedule actually changes) must flip
      `acknowledged` back to `false` **and re-trigger a push** — not get
      silently swallowed by this phase's dedup logic thinking the pair was
      already handled.
- [ ] **Sequencing dependency.** The push fires on the same severity
      threshold Phase 3 calibrates for UI display, not an independently
      invented one — pushing on every `Minor` flag risks the same
      notification fatigue Phase 3 exists to prevent.
- [ ] **Revocation — inherited for free, with direct precedent.**
      `can_access_user_data`'s predicate requires `status = 'active'` on the
      care link, so a revoked link fails it immediately, same as it already
      does for `Medicines`/`Schedules`/`DoseLogs`. Worth citing why this
      isn't hypothetical: `20260824130000_revoked_care_link_unreadable.sql`
      exists specifically because `care_links_read_own` once let a revoked
      caregiver keep reading the link row (phone numbers included) after
      revocation. Reusing `can_access_user_data` here sidesteps that exact
      class of bug by construction, on a codebase that's already been
      bitten by it once.

## Phase 3 — Tuning

There is no ground-truth database to tune against anymore, which changes
what "tuning" means here: it's instrumentation and a regression gate, not
prompt tweaking against a known-correct answer key.

- [ ] **Severity-surfacing thresholds — check vs. display, not check vs.
      skip.** Every check still runs and every result still gets stored
      (Phase 1 has no "don't bother checking Minor cases" mode) — the
      threshold only governs which stored flags get an interruptive UI
      treatment and a push. Only `Major` interrupts; `Moderate`/`Minor` sit
      in a collapsed list, still visible, just not pushed at. A confidence
      floor on display (e.g. don't render below `confidence: 0.6`) enforced
      app-side, not left to the model's own restraint alone. Start with
      these as defaults, not final numbers — real calibration needs the
      confidence distribution the Telemetry item below is instrumenting for,
      so ship the instrumentation before the first threshold change, not
      after.
- [ ] **Acknowledge invalidation — scoped to substantive changes only.** An
      acknowledgment is tied to the `checkedAt` snapshot it was made
      against. Re-triggering happens automatically through Phase 1's normal
      edit trigger whenever the drug identity, dose, or strength changes —
      this isn't a second mechanism, it's the existing trigger already
      firing a fresh check. What needs deciding here is the boundary:
      editing a medicine's *notes* or a schedule's *reminder time* shouldn't
      invalidate an acknowledgment or re-push anything, since neither could
      plausibly change the interaction verdict — only fields the model
      actually saw (drug name, strength, dose amount) should count. Get this
      boundary wrong in the strict direction and acknowledgments become
      fragile, re-nagging on every trivial edit — exactly what Phase 2's
      "acknowledge" mechanism exists to prevent.
- [ ] **Regression harness — file format.** A git-tracked fixture colocated
      with the edge function, same pattern as `parse-medicine`'s
      `extraction_test.ts`/`quota_test.ts` — e.g.
      `check-interaction/regression_cases.json`, each case naming its
      drugs, expected flags (or none), and how it was established. Seed it
      with the combo list from Phase 1's manual verification, **plus
      negative controls** — known-safe, commonly co-prescribed combos (e.g.
      Metformin + Amlodipine) with no expected flag. The seed list so far is
      all known-dangerous pairs; without negative cases nothing catches a
      prompt regression that starts over-flagging everything, which is the
      same notification-fatigue risk the severity thresholds above exist to
      prevent.
- [ ] **Asymmetric pass/fail.** A previously-expected flag disappearing or
      downgrading in severity is a hard fail that blocks the change — a
      known-dangerous pair silently losing its warning is the one outcome
      this harness exists to catch. A new flag appearing, or an existing one
      upgrading in severity, is not a fail — it's flagged for human review,
      since the model finding something new isn't necessarily wrong.
      Auto-blocking on that outcome would fight against the model ever
      improving.
- [ ] **Execution model.** A manually-triggered script, not routine CI — run
      specifically before shipping a system-prompt edit or model-version
      bump. It has to hit the live API to mean anything, which makes it a
      real cost line and a source of flakiness if run on every push. Output
      is a structured report in three buckets (regression / needs-review /
      matched), for a person to read before approving — not a bare
      pass/fail.
- [ ] **Growth mechanism.** Cannot be sourced from the aggregate telemetry
      above — "counts only, never drug names" means the analytics pipeline
      structurally can't produce a labeled case naming a specific pair.
      Needs its own path: a distinct, opt-in "this doesn't seem right"
      action on a flag (separate from the routine acknowledge in Phase 2),
      which sends that specific pair to a small reviewed queue — not
      analytics — for a person to check against real clinical reasoning
      before promoting it into the regression file. A user's dismissal
      isn't auto-trusted either; they can be wrong too. This needs its own
      consent coverage — word the Phase 1 `interactionCheck` consent
      sentence broadly enough to cover it now, rather than force a second
      re-consent event later, the same gap Phase 2 already flagged for
      `careShare`.
- [ ] **Drift detection.** Periodically re-run a sample of already-cached
      flags through the current prompt and diff against the stored
      severity — nothing guarantees identical output across model versions
      even at `temperature: 0`. Weight the sample toward `Major`-severity
      flags rather than a uniform random draw — a drifted `Minor` is a
      nuisance, a drifted `Major` is the failure this whole plan exists to
      catch, so spend the (small) re-check budget where it matters most. A
      changed answer is logged into the **same reviewed queue** the growth
      mechanism above already needs, not a second inbox — one place a
      person checks, not two.
- [ ] **QA audit against a real database, internal only.** Conditional on
      the DDInter commercial-license question (Appendix) or a paid vendor
      ever being worth it — not a blocking item. If it happens: same
      manually-triggered execution model as the regression harness, and the
      same three-bucket report shape, just diffing the regression file's
      cases against the external source instead of against a previous
      prompt version. Runs against the curated regression list, never real
      user data — sidesteps both the licensing and consent questions that
      blocked it as a production source.
- [ ] **Telemetry — no existing pipeline to attach to.** Flag counts by
      severity, dismiss/acknowledge rates, confidence distribution —
      aggregate counts only, never drug names or reasoning text, same "no
      advertising identifiers, minimal collection" line already drawn in
      `PRIVACY.md`. Worth being honest this isn't "wire up the existing
      system" — `SentryConfig.dsn` is `''` today, which is Sentry's
      documented way of fully disabling the SDK, and nothing else in this
      codebase collects aggregate usage events. This item depends on
      standing up *some* lightweight mechanism first (even a local counter
      table synced periodically), not assuming a hook that doesn't exist
      yet.

---

## Open questions

Answer these when the phase that needs them arrives, not before.

- Exact confidence/severity display thresholds in Phase 3 — needs real
  usage data, not a number picked in the abstract.
- Whether the DDInter team grants a commercial-use exception if asked
  (their terms are a standard academic-lab license; groups like this often
  do for legitimate, non-predatory apps). Worth a short email regardless of
  whether it's ever used for more than the internal QA role in Phase 3.
- Whether `Minor`-severity flags are worth surfacing to the caregiver at
  all, or should stay patient-side only, once Phase 2 is live and real
  push volume is visible.

## Appendix — why the database path was dropped

Tested directly, not assumed:

- **NIH/NLM's own Drug-Drug Interaction API was discontinued January 2024**
  and has not returned; only RxNorm's name-normalization endpoints are still
  free. ([RxLabelGuard migration guide](https://www.rxlabelguard.com/blog/nlm-rxnav-drug-interaction-api-discontinued-migration-guide),
  [DrugBank's own writeup](https://blog.drugbank.com/nih-discontinues-their-drug-interaction-api/))
- **DrugBank / Micromedex / Lexicomp** are enterprise-only — five-to-six
  figures a year, sales-quote pricing, built for hospital systems.
- **DDInter 2.0** ([ddinter2.scbdd.com](https://ddinter2.scbdd.com/)) is
  free, peer-reviewed (*Nucleic Acids Research*), and self-hostable — but
  its `/terms/` page states the data is licensed **CC BY-NC-SA 4.0**,
  explicitly "personal, non-commercial, informational or scholarly use"
  only. Using it server-side without redistributing the raw file does not
  avoid this — NC restricts the *use*, not just file redistribution, and a
  feature inside a commercial app (even a free-tier one whose stated purpose
  is building trust toward a paid tier) is the kind of use CC's own FAQ
  treats as commercial.
- Its bulk CSV export was downloaded and tested anyway, under the
  license's permitted non-commercial/informational use, purely to evaluate
  data quality independent of the licensing question:
  - Correctly flagged Warfarin+NSAID-class, Atorvastatin/Simvastatin+
    Clarithromycin as Major — matches real clinical guidance.
  - **Missed** Lisinopril+Spironolactone (the classic ACE-inhibitor +
    potassium-sparing-diuretic hyperkalemia combo) entirely — absent from
    the dataset, not just low-severity.
  - Diazepam+Alprazolam present but graded `"Unknown"` — not actionable.
  - Name matching is brittle even for English: `"Aspirin"` resolves to
    nothing; the dataset only recognizes `"Acetylsalicylic acid"`. Indian
    brand names (`Dolo 650`, `Crocin Advance`) fail outright with no alias
    table — this is what motivated dropping a separate normalization stage
    in favor of letting Claude resolve names as part of the same call.
- **RxLabelGuard** (a cheap commercial wrapper, $20/mo dev tier) sources its
  interaction data from **FDA Structured Product Labeling** — i.e. text
  parsed from each drug's own FDA label, not a curated bidirectional
  clinical database. Coverage depends on what each manufacturer chose to
  disclose on their own label, and Indian-market generics without a US FDA
  filing likely have thin-to-no coverage. Checked via public docs only; no
  account was created and no live call was made.
- Prototype script and downloaded DDInter CSVs (non-commercial/informational
  use, not part of the shipped app) live outside this repo, in scratch space
  from the scoping session — not committed, since none of it can ship as-is.
