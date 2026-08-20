# 3.5 — Breach response

**Controller:** Sagnik Das.
**Reachable contact:** sagnikd91@gmail.com (same as the privacy contact).
**Date:** 20 August 2026.

GDPR Art. 33/34, UK GDPR, and the FTC Health Breach Notification Rule
(16 CFR 318) all apply to some incidents involving this app. Washington
MHMD has its own notification rules if Washington consumers are involved.

A "breach" here includes **accidental alteration** (Art. 4(12)), not only
a hacker.

## Detection

There is no SIEM and no 24/7 monitor. Detection is:

- Operator noticing (SQL, Sentry if it is ever enabled, user email).
- Adversarial tests and migrations that assert invariants (the timestamp
  fix caught itself with `scheduled_at > now()`).
- A user or caregiver reporting a wrong time, a false missed dose, or an
  unexpected family link.

That is thin. It is honest. Improving detection is 4.1 (access log) and
operator MFA (4.4), not a pretend SOC.

## When you find something

1. **Stop the bleeding.** Disable the bad client, revoke a care link,
   rotate a key, take the edge function off, whatever actually contains it.
2. **Write a register row the same day** (template below), even if you
   later decide not to notify anyone. Art. 33(5) requires a record of
   *all* breaches.
3. **Threshold.**
   - **GDPR Art. 33:** notify the lead supervisory authority within 72
     hours unless the breach is unlikely to result in a risk to people.
     For an India-based controller with EEA users, that is the SA of the
     representative's member state once Art. 27 is in place; until then,
     treat the ICO or the user's SA as the practical addressee and do
     not hide behind "we have no representative."
   - **Art. 34:** tell affected people without undue delay if the risk is
     **high** (health data, wrong adherence information to a family
     member, a stranger seeing medicines).
   - **FTC HBNR:** unauthorised acquisition of identifying information +
     health info. Notify as the Rule requires if US persons are in scope.
   - **MHMD:** if Washington consumer health data is involved, follow
     MHMD's timeline in addition.
4. **Do not wait for perfect facts.** Send an update later. The register
   row can say "assessment in progress."

## Register

Append-only. Never delete a row. Status may change from open → closed.

### Template

```
ID:
Discovered (UTC):
Period of incident:
Art. 4(12) type: confidentiality / integrity / availability
Systems: (app build, hosted project twybepxnqayypzljhcnx, table names)
Data categories:
People affected (count, geographies if known):
How found:
Immediate containment:
Risk to people:
Notify SA? (yes/no + why)
Notify people? (yes/no + why)
Notify FTC / AG? (yes/no + why)
Closed (UTC):
```

### B-2026-08-19-A — Naive client timestamps

- **Discovered:** 19 August 2026, during investigation of dose-feed times
  that did not match any alarm.
- **Period:** From the first client-stamped write until
  `SyncService.isoUtc` shipped and migration
  `20260819120000_fix_naive_client_timestamps.sql` ran. Exact start is
  the first production write of `medicines` / `schedules` / `dose_logs`.
- **Type:** Integrity (accidental alteration). Confidentiality not
  implicated: no extra recipient.
- **What:** `DateTime.toIso8601String()` on a local Dart timestamp emits
  no offset. Postgres read the string as UTC. A 09:00 IST dose was stored
  as 09:00Z and shown to a linked family member as 14:30 IST. Device-side
  alarms were always correct. The damage was the *other* side of a care
  link, and any missed-dose FCM body quoting that time.
- **People:** Every signed-in user whose profile had a timezone and who
  had client-stamped rows. Users with no recorded timezone were left
  unshifted (unknowable offset).
- **Containment:** App writes `Z`; hosted rows with a known timezone were
  shifted back. Pre-fix clients must not remain in production.
- **Risk:** Medium for anyone with an active Care Link (wrong health
  times, possible wrong due-time in a notification). Low if no link
  existed.
- **Notify SA?** No. No evidence of EEA/UK data subjects in the live
  project at the time; the alteration was integrity toward an intended
  recipient, not acquisition by a stranger. Revisit if an EU user is
  later shown to have been in that dataset.
- **Notify people?** Not as a statutory Art. 34 blast. Anyone with a
  Care Link who still sees a wrong time should be told to update the app
  and re-check the feed. Recorded here so that decision is reviewable.
- **Closed:** 19 August 2026 (migration applied; app fix shipped).

### B-2026-08-19-B — Fabricated missed doses

- **Discovered:** Same investigation window. `PLAN.md` Known gaps.
- **Type:** Integrity. False health events (missed doses) written for
  times no reminder had been armed.
- **What:** `MissedDoseDetector` treated a new schedule as if it had
  existed for the whole lookback. Saving an 08:00 reminder at 09:00
  reported prior 08:00 slots as skipped. **Nine of eleven** live
  missed-dose rows were created that way. After push, each would have
  been a notification to a family member.
- **Containment:** `wasArmed` bounds occurrences on `schedules.updatedAt`.
  Silence beats a false alarm. Historical fabricated rows were not
  automatically deleted (dose logs are append-only); users can attach a
  contest note (Phase 2.4).
- **Risk:** High *if* push had delivered those rows to a caregiver. At
  discovery, treat as: false health events in the database, push path
  subsequently launched.
- **Notify SA?** No, same geography assessment as A. The register exists
  so this is not "undocumented."
- **Notify people?** If a specific caregiver received a false missed-dose
  alert, tell them. Do not send a general "you might have a false row"
  to everyone.
- **Closed:** 19 August 2026 (detector bound). Residual product behaviour
  is in [DPIA.md](DPIA.md) R1.

## Contact list (keep off git if numbers are private)

- Controller email: sagnikd91@gmail.com
- Supervisory authority: once Art. 27 exists, the representative's SA;
  UK users: ICO (ico.org.uk)
- Supabase support / status page
- Google Cloud support (FCM)
- Anthropic support (parse-medicine)
