# Dosely — Care Link plan

The working plan for turning Dosely from a single-user pill reminder into
something an elderly parent and one adult child in another city use together.
Updated as work lands; the design rationale behind these choices lives in the
Care Link spec artifact. How the app makes money is in `MONETIZE.md`, not here.

**Last updated:** 2026-08-20 · Phase 3 on `feature/phase-3-care-extras`

---

## Locked decisions

These are settled. Revisit them deliberately, not incidentally.

| Decision | Choice |
|---|---|
| Pairing | **Exactly one caregiver to one parent.** Each person belongs to at most one live pair. |
| Editing | **Either side can add or edit medicines. The caregiver cannot delete.** |
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
- Push in both directions: `device_tokens` + `care_alerts`, `notify-care`, FCM
  registration, and the inbound silent message that pulls and re-arms
- A privacy policy (Art. 13 rewrite), consent, local-only, account deletion,
  and the Phase 4 technical leftovers (OCR redaction, private care alerts,
  device-credential unlock)
- Caregiver editing (remote writes under the patient's `user_id`, no delete),
  silent `data_changed` both ways, per-medicine change history, and setup
  health on the Care Screen (#54)

**On this branch, not yet merged:** refill tracking, a Call button on a
missed-dose path, silent-device detection from `last_seen_at`, and
every-X-hours missed doses on the same lattice the alarms use.

**Live on the hosted Supabase project** (`twybepxnqayypzljhcnx`): migrations
applied, including the timestamp correction (2026-08-19, after both phones were
on a build that sends UTC). Edge functions deployed. Google provider configured
with the Web and Android client IDs; email sign-in and the custom SMTP sender
both disabled.

**Live on Firebase** (`decent-digit-135023`, the same Google Cloud project as
sign-in): Android app registered for `com.sagnikdas.dosely`, and the service
account stored as the `FCM_SERVICE_ACCOUNT` secret.

**Verification:** Phase 0's device testing is done — see below. Phase 1's happy
path was verified on two phones on 2026-08-19. Four accident cases still need
hardware; they are listed under Phase 1 and in the README.

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

## Phase 1 — Push — **done**

The binding constraint. Three later items are worth little without it, and
one existing feature is quietly dishonest until it exists.

- [x] FCM project setup; `google-services.json`
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

**Verified on hardware**, 2026-08-19, two phones and two Google accounts:

- [x] A missed dose on the parent's phone reaches the caregiver's phone. One
      reminder set two minutes out and ignored produced exactly one alert —
      `dfdf`, due 16:19, `delivered_count = 1` — and the notification arrived
- [x] It reports **one** dose, not three. Backdating used to manufacture a
      phantom miss for every day in the lookback; `wasArmed` closed that
- [x] It quotes the time the reminder was actually set for. Before the
      timestamp fix the same alert would have read 21:49
- [x] It lands in the *care* channel rather than the alarm channel, so it does
      not loop its sound until dismissed
- [x] Tapping it opens the parent's feed
- [x] Already-announced doses are never announced again — three earlier alerts
      stayed at three across repeated foregrounds

**Not yet exercised on hardware.** None of these blocks the phase; each is a
distinct failure mode that only shows up under a specific accident. The
mechanisms are covered by tests (unique index, token possession, `isStale`,
tap routing); the README lists the device steps.

- [ ] Two devices signed into one account announce a missed dose **once**
      (`care_alerts` unique on `(link_id, dose_log_id)`; `push_rls_test.sql`)
- [ ] Sign out on one phone, sign in as the other account, confirm the first
      account's alerts stop arriving there — `unregisterToken` runs before
      the session is cleared; `register_device_token` moves the row only
      with the same install id
- [ ] Uninstall the caregiver's app, raise an alert, confirm the token is
      pruned rather than retried forever (`fcm_test.ts` `isStale`)
- [ ] The cold-start tap path specifically (`getInitialMessage`), as opposed
      to the app-alive one that was tested. The message is now consumed
      once and opened after the first frame, same deferral as a local
      notification, so it does not race the navigator or replay on a
      later sign-in. A device-credential lock still covers the feed until
      unlock — the tap must not put medicine names on the lock screen.

The inbound direction could not be verified end-to-end until Phase 2 produced
a caregiver-side edit. That screen exists on `main` (#54); hardware
verification of inbound re-arm is the remaining check.

## Phase 2 — What push makes honest — **done**

- [x] **Caregiver-side editing.** Care Screen → Their reminders. Writes go
      straight to Supabase under the patient's `user_id`. This phone's Drift
      file is not touched, so alarms cannot fire on the wrong device. Scan
      and voice stay on the patient's phone — those would send a label under
      the caregiver's Anthropic consent. Attribution — "changed by Priya,
      Tuesday" — on both lists. `updated_by` is stamped from the JWT, not
      the payload.
- [x] Notify the other side on a change. `data_changed` is now either side
      of an active link; the silent message goes to the other person. Still
      no notification block (lock-screen / 4.3d, and the open question about
      what the parent is told is still open).
- [x] Per-medicine change history (`medicine_edits`, append-only, trigger)
- [x] **Setup health.** Notifications, exact alarms, battery exemption,
      armed count, last check-in. Written by the owner; shown on Care
      Screen to both sides.

Setup health matters more than it sounds. A skipped permission leaves the app
looking perfectly healthy and simply never firing, so the caregiver stops
worrying for the wrong reason — worse than having no app.

## Phase 3 — Small and independent — **on this branch**

Good candidates for picking up in any order once Phase 1 exists.

- [x] **Refill tracking** — tablet count decrementing per Taken on the
      patient's phone, warning at about five days left. Caregiver sees the
      same warning and can type a new count when they buy a bottle. A
      nameless `refill_low` ping goes to the caregiver, one per link per day.
- [x] **Call button** — each side stores their own number on the link.
      Call sits on the Care screen, on the dose feed a missed-dose tap
      opens, and as a notification action when the app drew the alert.
- [x] **Silent-device detection** — `silent_devices_due()` over
      `last_seen_at`; `notify-care` with `x-cron-secret` sends
      `device_silent`. Distinct from a missed dose: this fires when the
      app did not run. Schedule hourly once `CRON_SECRET` is set.
- [x] **Every-X-hours missed detection** — `intervalDoseSequence` is
      shared by the alarm scheduler and `expectedDoses`. Origin is the
      first parseable time on the calendar day the current definition
      started (`updatedAt`).

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
- **Every-X-hours doses share one lattice** between the alarm scheduler
  and missed-dose detection (`intervalDoseSequence`). Residual: the origin
  is the calendar day of `updatedAt`, so an edit still forfeits not-yet-
  recorded backfill before it — the same `wasArmed` rule as daily reminders.
- **A missed dose is only noticed while the parent's app runs.** The sweep is
  device-side, on foreground, so a parent who does not open the app for two
  days generates no missed doses and therefore no missed-dose alerts.
  Silent-device detection covers the "the app did not run" case, which is
  why a caregiver should never read "no missed-dose alerts" as "all is well".
- **A caregiver's edit re-arms the parent's alarms** via the silent
  `data_changed` push (Phase 2). Residual: the parent's phone still has to
  be reachable by FCM. If it is offline or force-stopped in a way that
  drops data messages, the change sits until the next foreground pull.
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
