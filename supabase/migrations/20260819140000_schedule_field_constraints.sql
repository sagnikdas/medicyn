-- Refuse to store a schedule no device can arm.
--
-- `frequency_type`, `times`, `days_of_week` and `interval_hours` had no
-- constraints at all, so Postgres accepted a `frequency_type` of 'hourly', a
-- `days_of_week` of {9}, and an `interval_hours` of 0 — none of which any
-- client can turn into an alarm. Two of those were enough to leave a phone
-- with no medication reminders whatsoever: the scheduler cancels every armed
-- alarm before re-arming, and both values made the re-arm loop
-- non-terminating.
--
-- The clients now validate on the way in and the scheduler guards itself on
-- the way out, but neither is the last word. Row-level security lets a linked
-- caregiver write another person's `schedules` row, so these values arrive
-- from a device the affected phone does not control and cannot vouch for; and
-- an older build that predates the client-side validation is still installed
-- and still syncing. The database is the only layer both of those pass
-- through, which is what makes it the right place for the invariant to live.
--
-- Every one of the 22 rows on the hosted project satisfies these already, so
-- the constraints validate immediately rather than being added NOT VALID.

-- `times` is jsonb, so its rule needs a function: a CHECK cannot contain the
-- subquery that walking the array requires.
--
-- Not SECURITY DEFINER — it runs as whoever is writing the row, so it needs
-- no elevated rights. The pinned `search_path` follows `generate_invite_code`
-- in the care-links migration: it keeps the operators here resolving to
-- pg_catalog regardless of the caller's setting.
create or replace function public.is_clock_time_array(value jsonb)
returns boolean
language sql
immutable
parallel safe
set search_path = pg_catalog, pg_temp
as $$
  select jsonb_typeof(value) = 'array'
     and not exists (
       select 1
         from jsonb_array_elements(value) as element
        where jsonb_typeof(element) <> 'string'
           -- A single-digit hour is accepted because the clients accept it —
           -- "9:05" names an unambiguous time, and rejecting it here would
           -- fail a sync for a value the app itself considers valid. An
           -- out-of-range hour is not: Postgres would store it happily and
           -- the device would roll "29:00" over into the next day, arming
           -- the alarm at a time nobody chose.
           or (element #>> '{}') !~ '^([01]?[0-9]|2[0-3]):[0-5][0-9]$'
     );
$$;

comment on function public.is_clock_time_array(jsonb) is
  'True when the value is a jsonb array of HH:mm strings with hour 0-23 and minute 0-59.';

alter table public.schedules
  add constraint schedules_frequency_type_known
  check (frequency_type in ('daily', 'specificDays', 'everyXHours', 'asNeeded'));

alter table public.schedules
  add constraint schedules_times_are_clock_times
  check (public.is_clock_time_array(times));

-- `<@` is array containment, which is exactly the rule: every element must be
-- one of the seven days. It is indifferent to order and duplicates, which the
-- clients already normalise away, and an empty array passes — correct, since
-- a schedule that is not `specificDays` carries no days at all.
alter table public.schedules
  add constraint schedules_days_of_week_in_range
  check (days_of_week <@ array[0, 1, 2, 3, 4, 5, 6]);

-- Null means "not set", and every-X-hours schedules fall back to the client's
-- 8-hour default. Zero is the value that never advances the walk looking for
-- the next dose; the upper bound is the tool schema's own.
alter table public.schedules
  add constraint schedules_interval_hours_in_range
  check (interval_hours is null or (interval_hours between 1 and 24));

-- Same class of defect, one table over: `dose_logs.action` is read back with
-- `DoseAction.values.byName`, which throws rather than defaulting, and the
-- dose-history screen renders every log through it. A caregiver has write
-- access to these rows too. All 43 existing logs are already one of the three.
alter table public.dose_logs
  add constraint dose_logs_action_known
  check (action in ('taken', 'snoozed', 'missed'));

-- Deliberately not added: cross-field rules, such as requiring a non-empty
-- `days_of_week` when `frequency_type` is 'specificDays', or forbidding an
-- `interval_hours` on a schedule that is not 'everyXHours'. Each is defensible
-- and each would reject a row some existing client can still produce, so they
-- want their own migration and their own look at the data first. These four
-- are value-domain rules only: they say what a column may contain, never how
-- two columns must agree.
