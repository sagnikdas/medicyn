# Dosely — Care Link plan

The working plan for turning Dosely from a single-user pill reminder into
something an elderly parent and one adult child in another city use together.
Updated as work lands; the design rationale behind these choices lives in the
Care Link spec artifact.

**Last updated:** 2026-08-19 · `main` @ `da2488d`, plus the Phase 1 push branch

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

**On the Phase 1 branch, not yet merged:** push in both directions —
`device_tokens` + `care_alerts`, the `notify-care` edge function, FCM
registration and refresh on the client, and the inbound silent message that
pulls and re-arms. Plus two fixes push turned from quiet wrongness into a
wrong notification on a family member's phone: retroactive missed doses
(below), and client timestamps that reached Postgres with no UTC offset —
every dose time and every `updated_at` was shifted by the writing device's
offset, so a 09:00 reminder read back as 14:30 to the other side. The
device was always right; only what the *other* person saw was wrong. A
migration corrects the existing history, shifting each row by its owner's
recorded timezone.

**Live on the hosted Supabase project** (`twybepxnqayypzljhcnx`): the first four
migrations applied; Google provider configured with the Web and Android client
IDs; email sign-in and the custom SMTP sender both disabled. The push migration
and `notify-care` are **not** deployed yet, and neither is the Firebase project
they need.

**Verification:** `flutter analyze` clean, `flutter test` 81/81, 34 adversarial
RLS assertions against a scratch Postgres (16 care-link, 18 push), and 6 Deno
tests over the stale-token rule. Phase 0's device testing is done — see below.

---

## Phase 0 — Prove it on real devices — **done**

Passed on two physical phones, 2026-08-19. Around two thousand lines had
merged without ever running on hardware; all of it behaves as specified.

- [x] Two Google accounts on two physical phones
- [x] Full link: invite → read code aloud → claim → confirm → connected
- [x] Feed shows real dose logs, and both sides see the identical screen
- [x] Leave a reminder unanswered overnight; confirm it appears as **Missed**
- [x] Install the new build **over** an existing one — the on-device schema
      goes v1 → v2 and that migration has never run on real data
- [x] Confirm alarms still fire after the `reconcile` change (one blanket
      cancel replaced per-schedule cancels)

## Phase 1 — Push — **built, awaiting device verification**

The binding constraint. Three later items are worth little without it, and
one existing feature is quietly dishonest until it exists.

- [ ] FCM project setup; `google-services.json` — **the one item only you can
      do.** Browser work in the Firebase console plus one `supabase secrets
      set`; the walkthrough is README → Push → "Enabling push"
- [x] `device_tokens` table, with registration and refresh on the client
- [x] **Outbound:** the parent's device calls `notify-care` after pushing a
      missed dose → the caregiver gets a visible alert
- [x] **Inbound:** silent data message to the parent's device on a schedule
      change → pull → re-arm alarms
- [x] Handle a token that has gone stale (app uninstalled, notifications off)

The inbound direction is the one that is easy to forget. Without it, a
schedule changed on the caregiver's phone does not reach the parent's alarms
until they next open the app — which could be a week, while the caregiver
believes the change is live.

**Two decisions worth recording.** First, the *device* calls the edge function
rather than a Postgres trigger firing on the insert: a trigger needs `pg_net`,
which lives in the `extensions` schema every security-definer function here
deliberately excludes, plus a service key stored in the database — and it would
catch nothing extra, since missed doses are only ever produced by the parent's
own device. Second, `device_tokens` is keyed by the FCM token itself, because a
token belongs to an app *install* and not an account; registering an existing
one moves the row, which is what stops a handed-back phone receiving the
previous person's alerts. RLS cannot express that move, so registration goes
through a security-definer function — the same shape as the link lifecycle.

**Still to verify on hardware**, once Firebase is set up:

- [ ] A missed dose on the parent's phone reaches the caregiver's phone,
      locked, within a minute or two. To manufacture one: set a reminder a
      couple of minutes out on the parent's phone, ignore the alarm, wait past
      the 30-minute grace, then foreground the app. Backdating a reminder no
      longer works — that was the retroactive bug, and it is fixed
- [ ] The alert lands in the *care* channel, not the alarm channel — it must
      not loop its sound until dismissed
- [ ] Tapping it opens the parent's feed, from both a cold start and a
      backgrounded app
- [ ] Two devices signed into one account announce a missed dose **once**
      (`care_alerts` is the de-duplication; check for a single row)
- [ ] Sign out on one phone, sign in as the other account, confirm the first
      account's alerts stop arriving there
- [ ] Uninstall the caregiver's app, raise an alert, confirm the token is
      pruned rather than retried forever

The inbound direction cannot be verified end-to-end until Phase 2, because
nothing yet produces a caregiver-side edit to push. The receiving half is
testable now by inserting a `data_changed` push by hand.

## Phase 2 — What push makes honest

- [ ] **Caregiver-side editing.** The database permits it and sync carries it;
      no screen does it. Needs the review/edit form to write under the
      patient's `user_id`, and attribution — "changed by Priya, Tuesday" — on
      both phones
- [ ] Notify the other side on a change — the silent push already exists
      (`CareNotifier.dataChanged`, wired into sync and inert until an edit
      belongs to someone other than the caller). Phase 2 widens the server's
      rule so the *caregiver* is told about the parent's changes too, which is
      what attribution needs
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

- **A sweep forfeits any backfill from before a schedule was last edited.**
  `MissedDoseDetector.wasArmed` bounds every occurrence on the schedule's
  `updatedAt`, because the alarms actually armed on the device always reflect
  its *current* definition. Without that bound, adding a reminder at nine in
  the morning reported three days of eight o'clock doses as skipped — nine of
  the eleven missed doses in the live database were fabricated that way, and
  since push landed each one would have been a notification on a family
  member's phone. The residual cost is that editing a reminder loses any
  not-yet-recorded backfill before the edit; sweeps run on every foreground, so
  in practice almost nothing is lost, and silence beats a false alarm.
- **Every-X-hours doses are never reported as missed.** The alarm scheduler
  re-anchors that sequence to today's anchor time on every run, so for an
  interval that does not divide 24, the slots armed yesterday are not the ones
  `expectedDoses` would compute today. Inventing occurrences that were never
  armed would tell a family their parent skipped medication that was never
  asked for. Silence beats a false alarm.
- **A caregiver's edit does not re-arm the parent's alarms** until they open
  the app. The push that fixes this is built (Phase 1) and inert, because no
  screen produces a caregiver-side edit yet. Still do not tell anyone that
  remote editing works — Phase 2 is what makes it true.
- **A missed dose is only noticed while the parent's app runs.** The sweep is
  device-side, on foreground, so a parent who does not open the app for two
  days generates no missed doses and therefore no alerts. This is the gap
  Phase 3's silent-device detection covers, and it is the reason a caregiver
  should never read "no alerts" as "all is well".
- **A missed-dose alert waits for the parent's phone to have connectivity.**
  If there is no network when the sweep runs, the alert goes out on the next
  foreground that has one — it is not late by minutes, it is late by however
  long the phone stays offline.
- **An alert is only offered for 24 hours** (`CareNotifier.announceWindow`).
  Every foreground re-offers every synced missed dose inside that window and
  the server drops what it has already sent, so a failed call costs latency
  rather than the alert. A dose missed longer ago than that is in the feed but
  will never ring a phone, which is deliberate: nobody can act on it by then.
- **The parent is told nothing when an alert fires.** Deliberate, and
  deliberately unresolved: see the open question below. `care_alerts` is
  readable by both sides, so whatever gets decided is implementable without a
  migration.
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

- **The timestamp correction assumes every row predates the fix.** It shifts
  by each owner's `profiles.timezone`, so it must be applied only once and
  only after every device is on a build that sends UTC — a phone still running
  an older one will re-shift whatever it pushes next. Rows whose owner has no
  recorded timezone are left alone rather than guessed at.

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
