# Dosely product and UX launch execution plan

**Plan date:** 26 August 2026

**Source audit:** [PRODUCT-UX-LAUNCH-AUDIT-2026-08-26.md](PRODUCT-UX-LAUNCH-AUDIT-2026-08-26.md)

**Source revision:** `origin/main` at `9e2f72d761aedb4fec9bb06a28d6a48336809ef8`

**Launch posture:** Closed beta after the Phase 1 gates pass; no public Google Play production launch until all production gates in this plan pass.

## 1. Executive sequence

The delivery order is:

> **Account privacy → scheduling correctness → visible reliability → release observability → activation → lifecycle completeness → family validation → closed beta → staged production → monetization**

This sequence deliberately puts user harm, privacy exposure, Play policy, and the ability to diagnose failures ahead of growth or feature breadth. Dosely's positioning should remain:

> **A private medication routine that works offline, with calm family backup when you want it.**

The free safety-critical loop must remain usable without an account, advertising, or a subscription.

## 2. How priorities are determined

Work is ordered using five criteria:

1. **Potential harm or privacy exposure:** Cross-account consent leakage and incorrectly timed or missing reminders come first.
2. **Public-launch blockers:** Play policy, public deletion/privacy routes, signing, and release credentials must be resolved before submission.
3. **Ability to detect failure:** Crash reporting, reminder-health state, diagnostics, and product events must exist before inviting external users.
4. **Dependency order:** A reliable single-user reminder loop precedes activation optimization; single-user reliability precedes family expansion; retention proof precedes billing.
5. **Evidence before expansion:** Advanced features and monetization follow measured activation, reliability, D7, and D30 results.

Policy/legal publishing and CI infrastructure can proceed alongside core engineering, but their exit gates are not optional.

## 3. Phase summary

| Phase | Timing | Primary objective | Audit coverage | Exit decision |
|---|---:|---|---|---|
| 1 | Weeks 1–2 | Eliminate privacy, safety, policy, and release blockers | P0-1 through P0-8; P1-13 | Permit controlled internal testing |
| 2 | Weeks 3–4 | Make first value fast, accessible, and trustworthy | P1-1 through P1-5; P1-10 through P1-14 | Permit observed external alpha |
| 3 | Weeks 5–6 | Complete the normal medicine lifecycle | P1-6 through P1-9; P1-15 and P1-16 | Permit broader closed beta scenarios |
| 4 | Weeks 7–8 | Prove the family-care differentiator | Care invite, connection, sync, and alert delivery | Permit 100–250-user beta |
| 5 | Weeks 9–10 | Meet quantitative beta and Play-readiness gates | Measurement, policy, listing, device matrix | Decide whether production can begin |
| 6 | Weeks 11–12 | Roll out production cautiously | Staged rollout and operating controls | Reach stable general availability |
| 7 | Post-launch | Invest based on retention and demand | Premium and advanced roadmap | Expand only when evidence supports it |

## 4. Phase 1 — Eliminate privacy, safety, and release blockers

### 4.1 Account isolation and data minimization

Implement first because current consent behavior can expose one person's choices to another account on the same device.

- Namespace every external-processing consent by Supabase user ID.
- Give local-only mode a separate owner identity.
- Keep device preferences—theme, display scale, onboarding state, and lock-screen privacy—separate from account processing preferences.
- Default a never-seen owner to all external processing off.
- Require an explicit choice before carrying local processing preferences into the first signed-in account.
- Detach foreground, opened-app, and token-refresh push listeners on sign-out.
- Make every asynchronous push callback verify the current owner.
- Register FCM only when care sharing or another remote-alert feature actually requires it.
- Align privacy and Data Safety descriptions with the final collection behavior.

**Acceptance:** A grants all choices, signs out, B signs in, and B begins with all processing off. No sync, token registration, AI, speech, or care call occurs before B grants the relevant choice. Returning to A restores only A's choices.

### 4.2 Scheduling correctness

Resolve core scheduling failure behavior before building presentation around it.

- Remove the silent UTC scheduling fallback.
- Keep timezone initialization retryable after transient failures.
- If the device timezone cannot be resolved, block normal scheduling and present Retry.
- Allow a fixed-offset degraded mode only when it is explicit and clearly warns about daylight-saving limitations.
- Record a redacted diagnostic failure without medicine data.
- Test invalid timezone identifiers, plugin failure, manual timezone changes, DST changes, reboot, upgrade, and cold start.

**Acceptance:** A reminder is never reported as successfully scheduled at a silently substituted UTC time.

### 4.3 Play-safe permission and notification strategy

The permission model must be settled before the reminder-health UI can accurately describe system state.

- Remove `USE_EXACT_ALARM` unless Play explicitly confirms eligibility.
- Use `SCHEDULE_EXACT_ALARM` with user-granted special access where exact timing is justified.
- Resolve whether direct battery-exemption and full-screen-intent declarations are supportable through policy/legal review.
- Request notification permission only while saving the first reminder that needs it.
- Request exact scheduling only after the user enables a reminder that needs it.
- Do not launch battery-exemption settings automatically on first Home load.
- Default to a high-priority heads-up notification with one sound.
- Offer **Gentle**, **Standard**, and explicitly opted-in **Persistent** modes.
- Degrade honestly to heads-up or inexact delivery when special access is unavailable.

**Acceptance:** Every denied or unavailable permission has a documented, tested fallback and an understandable recovery path.

### 4.4 Visible reminder health

Use the existing `ReconcileReport` rather than deleting it as unused plumbing.

- Persist notification permission state.
- Persist exact-alarm state: allowed, blocked, or not required.
- Persist the last reconciliation result and timestamp.
- Persist the next alarm expected time.
- Include battery-restriction state where Android exposes it reliably.
- Include push state for family alerts.
- Show **Reminder active** or **Not active—fix** for each relevant schedule.
- Show a non-dismissible Home warning when an active schedule is unarmed.
- Reconcile after returning from system settings, reboot, upgrade, and material schedule edits.
- Add a test-reminder action.

**Acceptance:** At least 95% of saved active schedules have an armed next reminder; every exception is shown as an explicit fix state rather than a false success.

### 4.5 Public policy infrastructure

- Publish permanent HTTPS `/privacy`, `/delete-account`, and `/support` pages.
- Make the account-deletion route functional outside the installed app.
- Document identity verification, deletion and retention categories, expected timing, and support response time.
- Update the app, offline privacy asset, Data Safety form, and Play Console with the same URLs and behavior.
- Add automated uptime and link checks.

**Acceptance:** All routes are public, non-geofenced, independent of private repository access, and usable by an uninstalled user.

### 4.6 Release proof and observability

- Configure Play App Signing and protect an upload key and recovery material.
- Build a signed release AAB.
- Register release SHA fingerprints for Google sign-in and Firebase.
- Add a root command that runs all Flutter, edge-function, migration/RLS, and dependency checks with the correct import maps.
- Add signed AAB creation to CI.
- Enable privacy-minimized release crash reporting.
- Add a typed event layer and written event dictionary.
- Add **Share diagnostics** for permissions, app version, OEM, last arm result, and sync state without medical content.
- Start the physical-device notification matrix before Phase 1 ends.

Crash reports and analytics must never include medicine names, dosage, OCR text, transcripts, email, care codes, raw database IDs, or precise health timestamps.

### Phase 1 exit gate

Do not begin an external beta until all of the following are true:

- No consent, push listener, or processing state leaks between accounts.
- No timezone error can silently change a reminder time.
- Every active schedule is visibly armed or visibly degraded.
- The restricted-permission strategy is documented and approved for submission.
- Public privacy, deletion, and support routes work.
- A signed internal AAB installs, authenticates, schedules, survives reboot, and reports redacted failures.

## 5. Phase 2 — Make first value fast and trustworthy

### 5.1 First-session activation

- Replace scanner-first Add with a chooser: **Scan label**, **Speak details**, and **Enter manually**.
- Ask for camera or microphone permission only after that method is selected.
- Reduce onboarding to one concise value/privacy screen.
- Let the user add and verify the first medicine before sign-in.
- Request notification and exact-timing access at Save, one permission at a time.
- Require confirmation of medicine name, amount, frequency, and times regardless of capture method.
- Show the next reminder and offer **Send a test reminder** after Save.
- Offer backup and family support only after the first local reminder is known to work or when explicitly selected.

### 5.2 Trust, resilience, and accessibility

- Change sign-in copy to promise the ability to enable backup, not automatic backup.
- Expose **Backup On/Off**, last successful sync, pending work, and Retry.
- Expose family connected/degraded state and alert activity.
- Replace raw exceptions with friendly actions and stable support codes.
- Put all busy-state paths in `try/catch/finally` and guard asynchronous UI callbacks.
- Render loading, retryable error, and successfully empty states separately.
- Respect the device text scaler and treat the app setting only as an optional multiplier or preset.
- Test at the Android maximum and at least 200% scaling.
- Give interactive controls a minimum 48dp target.
- Add user-controlled snooze choices, reminder intensity, response windows, and honest **unanswered** terminology.
- Fix the Insights **Most consistent** calculation and accessible chart semantics.

### Phase 2 exit gate

- A moderated new user can create and verify a reminder without assistance in under two minutes.
- Manual entry requires neither camera nor microphone access.
- Permission denial produces a visible and recoverable degraded state.
- Critical flows remain usable at maximum tested text scaling.
- Activation, permission, reminder-arm, and first-response funnels are measured without health data.

## 6. Phase 3 — Complete the medicine lifecycle

Implement schema and migration changes before their dependent UI work to reduce migration churn.

1. Add Active, Paused, Completed, and As-needed states.
2. Add start date, end date, pause-until, resume, and archive behavior while preserving history.
3. Add **Log dose now** for PRN medicine, optionally capturing amount and a user-authored reason.
4. Exclude PRN logs from adherence denominators.
5. Add auditable correction events; retain the original action and calculate from the latest valid correction.
6. Replace whole-tablet refill assumptions with quantity, unit, decimal consumption, refill transactions, and projected run-out.
7. Define a versioned complete export schema and delete sensitive temporary files in `finally`.
8. Externalize strings and use locale-aware date and time formatting.
9. Enable SQLite foreign keys after a cleanup migration and test deletion and retention behavior.
10. Limit history queries by date range and isolate clock-dependent rebuilds where profiling justifies it.

### Phase 3 exit gate

- Temporary courses, pauses, resumptions, completions, PRN doses, corrections, and refills pass end-to-end tests.
- Historical events survive lifecycle transitions.
- Metrics use corrections correctly and exclude PRN where appropriate.
- Export tests cover every intended persisted field and no sensitive temporary export remains behind.

## 7. Phase 4 — Prove the family-care differentiator

Family value follows—not precedes—a dependable single-user reminder loop.

- Add signed, expiring share links and QR with code fallback.
- Keep explicit patient confirmation before activating a care link.
- Make revocation and dependency changes clear.
- Display family Connected/Needs setup state.
- Display alert sent, delivered where knowable, and acknowledged state without overstating FCM guarantees.
- Test account switching, push during sign-out, offline changes, sync conflicts, killed-app delivery, reboot, and OEM power restrictions.
- Recruit and observe 20–30 medicine-taker/caregiver pairs.
- Run weekly interviews and prioritize unexplained connection or delivery failures over feature additions.

### Phase 4 exit gate

- At least 80% of observed dyads connect without developer assistance.
- No cross-account incidents occur.
- No alert failure is unexplained; all degraded states are visible and diagnosable.

## 8. Phase 5 — Closed beta and Google Play readiness

### 8.1 Store and policy preparation

- Complete Data Safety, Health Apps, content-rating, target-audience, ads, app-access, and permission declarations.
- Use the **Medication and Treatment Management** health category.
- Include clear non-medical-device and healthcare-professional language.
- Finalize the application ID before the first Play upload.
- Supply reviewer credentials and steps for backup and care features.
- Prepare high-contrast, large-UI store assets centered on offline use, privacy, family choice, and visible reminder health.
- Avoid claims about preventing missed doses, clinical validation, or health outcomes unless substantiated.

### 8.2 Device and beta coverage

- Exercise the exact signed AAB through Internal App Sharing and the closed track.
- Cover Pixel, Samsung, Motorola, Xiaomi/Redmi, and Oppo/Realme where practical for the India launch.
- Cover Android 7, 12, 13, 14, 15, and 16 where practical.
- Run Play pre-launch and accessibility reports.
- Run an India English beta with 100–250 users across the OEM mix.
- Establish a support workflow and price-discovery interviews.
- Fix reliability and activation issues before accepting new feature work.

### Phase 5 production gate

Treat the following as initial hypotheses and make a documented launch/no-launch decision:

- At least 65% of installers who open the app save one medicine.
- At least 75% grant notifications after the contextual prompt.
- At least 95% of saved active schedules have an armed next reminder or explicit fix state.
- At least 60% of activated users record a first dose response.
- Activated-user D7 retention is at least 35%.
- Activated-user D30 retention is at least 20%.
- Care-invite acceptance is at least 40% among users who create an invite.
- Crash-free users are at least 99.5%.
- There are zero known cross-account consent or data incidents.

Reliability failures must remain in the denominator.

## 9. Phase 6 — Controlled production rollout

- Ship the free safety-critical core first if billing is not fully proven.
- Roll out at 5% → 20% → 50% → 100%.
- Hold each stage for several days and until a meaningful volume of scheduled reminders has occurred.
- Monitor crashes, ANRs, reminder-arm failures, timezone failures, permission denial, care-alert delivery, support contacts, uninstalls, and reviews.
- Define rollback ownership and preserve a known-good signed artifact.
- Publish transparent release notes and provide fast support.

Pause a rollout stage for any consent leakage, silent unarmed schedule, silent timezone substitution, material crash/ANR regression, or unexplained family-alert failure.

## 10. Phase 7 — Post-launch investment

Build only after retention and reliability demonstrate demand:

- Doctor-ready PDF/CSV reports.
- Advanced schedule phases and travel-timezone assistance.
- Multiple caregivers and patients with role-based access.
- Escalation ladders with rate limits, quiet hours, and patient control.
- Home-screen widget or Android quick actions.
- One additional language selected from observed cohort demand.
- Dosely Plus, Dosely Family, and possibly Local Pro.
- Health Connect only when it removes a validated user problem.

### Monetization gates

Do not activate a public paywall until:

- Activated-user D30 retention is credible.
- Reminder delivery health is observable.
- Backup and restore pass on a second physical device.
- Family alerts have visible delivery/status UX.
- Purchase, restore, refund, grace-period, account-hold, account-switch, and deletion cases pass.
- Premium value is visible without restricting the free safety loop.

Keep reminders, Taken/Snooze/Skip, current medicines, privacy controls, export, and deletion free. Do not add behavioral advertising, medicine-targeted offers, or health-data sales.

## 11. Explicitly deferred work

Do not build these items during the launch program:

- Drug-interaction checking without a licensed, maintained clinical source and clinical/legal review.
- Automatic dose or prescribed-schedule changes from AI.
- A broad health tracker.
- Wearable apps without demonstrated demand.
- Pharmacy commerce based on medication data.
- Billing work that delays a safe free beta.

## 12. Measurement framework

**North-star metric:** Weekly protected doses—scheduled occurrences for activated users where the reminder was armed and the user recorded a response.

The core funnel is:

> Store view → install → Add started → first medicine saved → notification enabled → first reminder armed → first dose response → responses on three separate days → D7 → D30 → care invite created/accepted → trial → paid renewal

Events may include method, duration bucket, count bucket, permission type/result, OEM/API, non-sensitive error code, response action/lateness bucket, sync item-count bucket, and purchase state. They must not include medicine details, free text, personal identifiers, care codes, exact scheduled health timestamps, or raw database IDs.

## 13. Definition of launch success

Dosely is ready for broad acquisition only when users can:

1. Create a reminder quickly by their preferred method.
2. See that it is actually armed—or clearly understand how it is degraded.
3. Use the core loop offline and without an account.
4. Switch accounts without inheriting another person's choices or callbacks.
5. Trust public privacy and deletion promises outside the app.
6. Connect a family pair without developer assistance and see alert state honestly.
7. Complete the medicine lifecycle without losing history or corrupting metrics.

Monetization and feature breadth follow those outcomes; they do not substitute for them.
