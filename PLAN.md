# Dosely — Care Link plan

The working plan for turning Dosely from a single-user pill reminder into
something an elderly parent and one adult child in another city use together.
Updated as work lands; the design rationale behind these choices lives in the
Care Link spec artifact.

**Last updated:** 2026-08-18 · `main` @ `18dfdf3`

---

## Locked decisions

These are settled. Revisit them deliberately, not incidentally.

| Decision | Choice |
|---|---|
| Pairing | **Exactly one caregiver to one parent.** Each person belongs to at most one live pair. |
| Editing | **Either side can add or edit medicines.** |
| Visibility | **Full symmetry** — the parent sees exactly what the caregiver sees. |
| Consent | Two steps. Possession of an invite code is never access; the parent confirms the named person. |
| Roles | Never asked for. Whoever shows a code needs help, whoever types one in is giving it. |
| Conflicts | Last-write-wins on a client-stamped `updated_at`, made safe by showing who changed what. |
| Distribution | Android via Google Play. iOS not started. |

## Where it stands

**Shipped to `main`:**

- Google SSO as the only sign-in method; email/OTP and its SMTP sender removed
- Sync that carries an edit, not just an insert (`updated_at` / `updated_by`, last-write-wins pull)
- `care_links` + `profiles` + row-level security opening a parent's data to their caregiver
- The linking flow: invite, claim, confirm, disconnect
- The adherence feed — what happened with someone's medicines, punctuality first
- Missed-dose detection, written on the device that owns the reminders
- A privacy policy draft, and the app name capitalised

**Live on the hosted Supabase project** (`twybepxnqayypzljhcnx`): all four
migrations applied; Google provider configured with the Web and Android client
IDs; email sign-in and the custom SMTP sender both disabled.

**Verification:** `flutter analyze` clean, `flutter test` 52/52, and 16
adversarial RLS assertions passing against a scratch Postgres. **None of it
has run on a phone.**

---

## Phase 0 — Prove it on real devices

Nothing new gets built until this passes. Around two thousand lines have
merged without ever running on hardware, and every later phase compounds that
risk.

- [ ] Two Google accounts on two physical phones
- [ ] Full link: invite → read code aloud → claim → confirm → connected
- [ ] Feed shows real dose logs, and both sides see the identical screen
- [ ] Leave a reminder unanswered overnight; confirm it appears as **Missed**
- [ ] Install the new build **over** an existing one — the on-device schema
      goes v1 → v2 and that migration has never run on real data
- [ ] Confirm alarms still fire after the `reconcile` change (one blanket
      cancel replaced per-schedule cancels)

Every item here either confirms the last five merges or finds what is wrong
while it is still cheap to fix.

## Phase 1 — Push

The binding constraint. Three later items are worth little without it, and
one existing feature is quietly dishonest until it exists.

- [ ] FCM project setup; `google-services.json`
- [ ] `device_tokens` table, with registration and refresh on the client
- [ ] **Outbound:** edge function on a missed-dose insert → alert the caregiver
- [ ] **Inbound:** silent data message to the parent's device on a schedule
      change → pull → re-arm alarms
- [ ] Handle a token that has gone stale (app uninstalled, notifications off)

The inbound direction is the one that is easy to forget. Without it, a
schedule changed on the caregiver's phone does not reach the parent's alarms
until they next open the app — which could be a week, while the caregiver
believes the change is live.

## Phase 2 — What push makes honest

- [ ] **Caregiver-side editing.** The database permits it and sync carries it;
      no screen does it. Needs the review/edit form to write under the
      patient's `user_id`, and attribution — "changed by Priya, Tuesday" — on
      both phones
- [ ] Notify the other side on a change, using the same silent push
- [ ] Per-medicine change history
- [ ] **Setup health.** Whether the parent's phone can actually ring:
      notifications allowed, exact alarms permitted, battery exemption
      granted, alarms armed, last check-in. The device already knows all of
      it; it needs syncing and a panel on the caregiver's side

Setup health matters more than it sounds. A skipped permission leaves the app
looking perfectly healthy and simply never firing, so the caregiver stops
worrying for the wrong reason — worse than having no app.

## Phase 3 — Small and independent

Good candidates for picking up in any order once Phase 1 exists.

- [ ] **Refill tracking** — tablet count decrementing per dose, warning at
      about five days left
- [ ] **Call button** — one tap to phone, straight from a missed-dose alert
- [ ] **Silent-device detection** — scheduled job over `last_seen_at`,
      reporting "their phone hasn't checked in since yesterday". Distinct
      from a missed dose, and the signal a device-side design can never
      produce
- [ ] **Every-X-hours missed detection** — currently excluded on purpose (see
      Known gaps). Closing it means the alarm path and `expectedDoses`
      sharing one definition of the sequence

## Phase 4 — Shipping

**This phase's clock runs independently.** Closed testing takes weeks of
calendar time no matter what else is happening, so start it as soon as Phase 0
says the build is sound and let it run while Phases 1–3 proceed.

- [ ] Fill the three placeholders in `PRIVACY.md` — effective date, and
      support email in two places
- [ ] Host the policy at a public URL; Play will not accept a listing without one
- [ ] Release keystore and `app/android/key.properties` (see
      `app/README.md` → Release signing)
- [ ] Play Console: Data safety form, and it must agree with `PRIVACY.md`
- [ ] Declare `USE_EXACT_ALARM` and `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`
- [ ] `flutter build appbundle --release`, upload to internal testing
- [ ] Register an Android OAuth client for **each** SHA-1 Play shows — app
      signing key *and* upload key — and add both to Supabase's Client IDs
- [ ] Closed testing for the required period (check the current tester count
      and duration in Play Console; Google has changed it more than once)
- [ ] Store listing written **to the caregiver child**, not the parent — they
      are the one who discovers, installs and configures the app

---

## Open questions

Answer these when the phase that needs them arrives, not before.

- **Grace period before a dose counts as missed.** Currently a flat 30
  minutes. Too short and a family is alarmed over a slow breakfast; too long
  and the alert arrives after it could have helped. Probably wants to be
  per-medicine.
- **What the parent is told when an alert fires.** Silence undercuts the
  symmetry promise; "we told your daughter" could read as being told off.
- **Whether a caregiver can delete, or only add and edit.** Deletion is the
  one write with no undo, and the most likely to be done by the wrong person
  in a hurry.
- **What happens when a link is broken and remade** — a sibling taking over.
  The dose history belongs to the parent's account and should survive it, but
  that has to be deliberate rather than incidental.

## Known gaps

Real limitations in what is already merged. None are bugs; all are choices
worth remembering.

- **Every-X-hours doses are never reported as missed.** The alarm scheduler
  re-anchors that sequence to today's anchor time on every run, so for an
  interval that does not divide 24, the slots armed yesterday are not the ones
  `expectedDoses` would compute today. Inventing occurrences that were never
  armed would tell a family their parent skipped medication that was never
  asked for. Silence beats a false alarm.
- **A caregiver's edit does not re-arm the parent's alarms** until they open
  the app. Phase 1 closes this. Until then, do not tell anyone that remote
  editing works.
- **Sibling sharing is impossible** by design — one caregiver per parent.
  Widening from one to many later is a far easier migration than narrowing.
- **Nobody can be both** a parent and a caregiver, in different pairs.
- **Voice input is not on-device.** `SpeechListenOptions.onDevice` is left
  false, so the platform recogniser handles it and on most Android devices
  Google's servers see the audio. `PRIVACY.md` says so plainly. Setting it
  true is a one-line change that fails outright on devices with no offline
  model.
- **The `deleted` column** on `medicines` and `schedules` is dead — never set,
  absent from Postgres, superseded by `active = false`. Removing it needs a
  Drift migration, which is not worth the risk for an unused boolean.

## Conventions worth keeping

- Branch each PR from `main`. An earlier branch cut from another branch made
  its parent's commits invisible to GitHub's merge detection and left a PR
  that could only be closed, not merged.
- When stacking PRs anyway, **retarget the child to `main` before merging it.**
  GitHub only auto-retargets when the base branch is deleted on merge;
  otherwise the child merges into the already-merged parent, silently.
- Migrations go to the hosted project before the app build that needs them.
  The reverse breaks every write.
- The local RLS harness must not install extensions Supabase keeps elsewhere.
  A harness that makes a migration pass locally and fail remotely is worse
  than no harness.
