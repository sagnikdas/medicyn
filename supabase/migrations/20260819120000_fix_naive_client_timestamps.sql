-- Correct timestamps that were written without their UTC offset.
--
-- `DateTime.toIso8601String()` on a *local* Dart DateTime emits no offset —
-- `2026-08-19T09:00:00.000` — and Postgres reads a bare timestamp as UTC. Every
-- client-stamped column therefore landed shifted by the writing device's offset:
-- a 09:00 IST dose was stored as 09:00Z, which reads back as 14:30 IST.
--
-- Nothing on a device was ever wrong. Drift stores instants, so each phone's own
-- alarms and history were correct throughout, and nothing ever crashed. The
-- damage was entirely in what the *other* side of a care link was shown — the
-- dose feed, and since push landed, a notification quoting a family member a
-- time no alarm ever rang at. That is the whole point of the feature, so the
-- history is corrected rather than left to be read wrongly forever.
--
-- The app fix (SyncService.isoUtc) ships with this. Order matters: a phone still
-- running a pre-fix build will re-shift anything it pushes after this runs, so
-- update every device before applying it.
--
-- Only the columns a client actually sends are touched. `profiles.last_seen_at`
-- was always written with `.toUtc()` and is correct; `care_links`, `care_alerts`
-- and `device_tokens` are stamped by `now()` server-side and never had the bug.

-- Each row is shifted by *its own owner's* zone rather than a hardcoded +05:30.
-- `(ts at time zone 'UTC')` recovers the naive local wall-clock the device
-- actually meant; `at time zone p.timezone` then reads that wall-clock in the
-- zone it was written in. For a zone with DST this picks the offset in force on
-- the day in question, which a fixed interval could not.
--
-- Rows whose owner has no recorded timezone are deliberately left alone: the
-- offset they were written at is unknowable, and a guess would turn a knowably
-- wrong time into an unknowably wrong one.

update medicines m
   set created_at = (m.created_at at time zone 'UTC') at time zone p.timezone,
       updated_at = (m.updated_at at time zone 'UTC') at time zone p.timezone
  from profiles p
 where p.user_id = m.user_id
   and p.timezone is not null;

update schedules s
   set created_at = (s.created_at at time zone 'UTC') at time zone p.timezone,
       updated_at = (s.updated_at at time zone 'UTC') at time zone p.timezone
  from profiles p
 where p.user_id = s.user_id
   and p.timezone is not null;

update dose_logs d
   set scheduled_at = (d.scheduled_at at time zone 'UTC') at time zone p.timezone,
       logged_at    = (d.logged_at    at time zone 'UTC') at time zone p.timezone
  from profiles p
 where p.user_id = d.user_id
   and p.timezone is not null;

-- This migration edits health history on a live database, so it checks itself
-- rather than reporting success on faith.
--
-- The assertion is the universal one: nothing a client stamped can lie in the
-- future. A device cannot have recorded missing a dose that has not come round
-- yet, and nobody edits a reminder tomorrow. A wholesale positive shift — which
-- is what this bug is for any zone east of Greenwich — pushes recent rows past
-- `now()`, and that is exactly how the fault was first spotted.
--
-- Five minutes of slack, because `updated_at` is deliberately the client's own
-- clock (see the row_versioning migration) and a phone running slightly fast is
-- normal rather than corrupt.
--
-- Deliberately *not* asserted: that every daily dose lands on one of its
-- schedule's `times`. That is the sharper test, and the relation the bug
-- actually broke — but a schedule edited after a dose was recorded fails it
-- legitimately, so it is reported as a number to read rather than a reason to
-- abort.
do $$
declare
  future_rows int;
  matching int;
  total int;
begin
  select (select count(*) from dose_logs where scheduled_at > now() + interval '5 minutes')
       + (select count(*) from dose_logs where logged_at    > now() + interval '5 minutes')
       + (select count(*) from medicines where updated_at   > now() + interval '5 minutes')
       + (select count(*) from schedules where updated_at   > now() + interval '5 minutes')
    into future_rows;

  if future_rows > 0 then
    raise exception
      'timestamp correction leaves % client-stamped row(s) in the future', future_rows;
  end if;

  select count(*) filter (
           where jsonb_exists(s.times, to_char(d.scheduled_at at time zone p.timezone, 'HH24:MI'))
         ),
         count(*)
    into matching, total
    from dose_logs d
    join schedules s on s.id = d.schedule_id
    join profiles p on p.user_id = d.user_id
   where s.frequency_type = 'daily'
     and p.timezone is not null;

  raise notice
    'timestamp correction: %/% daily doses land on a time their schedule names',
    matching, total;
end;
$$;
