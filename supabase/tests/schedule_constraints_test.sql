-- Assertions for the schedule value-domain constraints.
--
-- Run against a database with every migration applied, as a role that can
-- write to auth.users (the local `postgres` superuser, or `supabase db
-- connect`):
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/schedule_constraints_test.sql
--
-- Everything runs inside a transaction that is rolled back.
--
-- These run as the table owner, deliberately bypassing row-level security.
-- RLS decides *who* may write a row; a CHECK decides what a row may say, and
-- it has to hold for every writer including the service role that the
-- `notify-care` function uses. The values below are the ones that actually
-- left a phone with no alarms.

begin;

\set owner '11111111-1111-1111-1111-111111111111'

insert into auth.users (id, email) values (:'owner', 'owner@test.invalid');

insert into medicines (id, user_id, drug_name)
values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', :'owner', 'Test');

create or replace function pg_temp.expect(ok boolean, what text) returns void
language plpgsql as $$
begin
  if not ok then
    raise exception 'FAILED: %', what;
  end if;
  raise notice 'ok: %', what;
end;
$$;

-- Distinguishes a constraint rejection from any other error, so a test cannot
-- pass because the statement failed for an unrelated reason.
create or replace function pg_temp.expect_rejected(stmt text, what text) returns void
language plpgsql as $$
begin
  begin
    execute stmt;
  exception
    when check_violation then
      raise notice 'ok: % (check_violation)', what;
      return;
    when others then
      raise exception 'FAILED: % — rejected, but with % not check_violation', what, sqlstate;
  end;
  raise exception 'FAILED: % — it was allowed', what;
end;
$$;

create or replace function pg_temp.expect_accepted(stmt text, what text) returns void
language plpgsql as $$
begin
  execute stmt;
  raise notice 'ok: %', what;
exception when others then
  raise exception 'FAILED: % — it was rejected (%: %)', what, sqlstate, sqlerrm;
end;
$$;

create or replace function pg_temp.insert_schedule(
  id text, frequency text, times text, days text, interval_hours text
) returns text language sql immutable as $$
  select format(
    'insert into schedules (id, medicine_id, user_id, frequency_type, times, days_of_week, interval_hours, active) '
    'values (%L, ''aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'', %L, %L, %L::jsonb, %s, %s, true)',
    id, '11111111-1111-1111-1111-111111111111', frequency, times, days, interval_hours
  );
$$;

-- ---------------------------------------------------------------------------
-- what must still be accepted
-- ---------------------------------------------------------------------------

select pg_temp.expect_accepted(
  pg_temp.insert_schedule(
  '00000000-0000-4000-8000-000000000001', 'daily', '["08:00","20:30"]', 'array[]::int[]', 'null'),
  'an ordinary daily schedule is accepted');

select pg_temp.expect_accepted(
  pg_temp.insert_schedule(
  '00000000-0000-4000-8000-000000000002', 'specificDays', '["09:00"]', 'array[0,3,6]', 'null'),
  'every day of the week is in range');

select pg_temp.expect_accepted(
  pg_temp.insert_schedule(
  '00000000-0000-4000-8000-000000000003', 'everyXHours', '["08:00"]', 'array[]::int[]', '24'),
  'the interval bounds are inclusive');

-- The clients accept a single-digit hour, so the database must too; rejecting
-- it would fail a sync for a value the app considers valid.
select pg_temp.expect_accepted(
  pg_temp.insert_schedule(
  '00000000-0000-4000-8000-000000000004', 'daily', '["9:05"]', 'array[]::int[]', 'null'),
  'a single-digit hour is accepted');

select pg_temp.expect_accepted(
  pg_temp.insert_schedule(
  '00000000-0000-4000-8000-000000000005', 'asNeeded', '[]', 'array[]::int[]', 'null'),
  'an as-needed schedule with no times is accepted');

-- ---------------------------------------------------------------------------
-- what must now be refused
-- ---------------------------------------------------------------------------

select pg_temp.expect_rejected(
  pg_temp.insert_schedule('00000000-0000-4000-8000-0000000000f1', 'hourly', '["09:00"]', 'array[]::int[]', 'null'),
  'a frequency_type naming nothing is refused');

select pg_temp.expect_rejected(
  pg_temp.insert_schedule('00000000-0000-4000-8000-0000000000f2', 'specificDays', '["09:00"]', 'array[9]', 'null'),
  'a day outside 0..6 is refused');

select pg_temp.expect_rejected(
  pg_temp.insert_schedule('00000000-0000-4000-8000-0000000000f3', 'specificDays', '["09:00"]', 'array[-1]', 'null'),
  'a negative day is refused');

select pg_temp.expect_rejected(
  pg_temp.insert_schedule('00000000-0000-4000-8000-0000000000f4', 'everyXHours', '["09:00"]', 'array[]::int[]', '0'),
  'an interval of zero is refused');

select pg_temp.expect_rejected(
  pg_temp.insert_schedule('00000000-0000-4000-8000-0000000000f5', 'everyXHours', '["09:00"]', 'array[]::int[]', '999'),
  'an absurd interval is refused');

select pg_temp.expect_rejected(
  pg_temp.insert_schedule('00000000-0000-4000-8000-0000000000f6', 'daily', '["9am"]', 'array[]::int[]', 'null'),
  'a time that is not a time is refused');

-- The schema pattern the model is given, ^[0-2][0-9]:[0-5][0-9]$, admits this.
select pg_temp.expect_rejected(
  pg_temp.insert_schedule('00000000-0000-4000-8000-0000000000f7', 'daily', '["29:00"]', 'array[]::int[]', 'null'),
  'an hour past 23 is refused, which the tool schema pattern would allow');

select pg_temp.expect_rejected(
  pg_temp.insert_schedule('00000000-0000-4000-8000-0000000000f8', 'daily', '["12:60"]', 'array[]::int[]', 'null'),
  'a minute past 59 is refused');

select pg_temp.expect_rejected(
  pg_temp.insert_schedule('00000000-0000-4000-8000-0000000000f9', 'daily', '"08:00"', 'array[]::int[]', 'null'),
  'a times value that is not an array is refused');

select pg_temp.expect_rejected(
  pg_temp.insert_schedule('00000000-0000-4000-8000-0000000000fa', 'daily', '[800]', 'array[]::int[]', 'null'),
  'a times element that is not a string is refused');

-- ---------------------------------------------------------------------------
-- an update is a write too
-- ---------------------------------------------------------------------------

-- The caregiver path that motivated this is an edit, not an insert.
select pg_temp.expect_rejected(
  'update schedules set interval_hours = 0 where id = ''00000000-0000-4000-8000-000000000003''',
  'an existing row cannot be updated into an unusable interval');

select pg_temp.expect_rejected(
  'update schedules set days_of_week = array[9] where id = ''00000000-0000-4000-8000-000000000002''',
  'an existing row cannot be updated into a day outside 0..6');

-- ---------------------------------------------------------------------------
-- dose_logs.action
-- ---------------------------------------------------------------------------

insert into dose_logs (id, schedule_id, user_id, scheduled_at, action)
values ('00000000-0000-4000-8000-00000000000a', '00000000-0000-4000-8000-000000000001',
        :'owner', now(), 'taken');
select pg_temp.expect(
  (select count(*) from dose_logs where id = '00000000-0000-4000-8000-00000000000a') = 1,
  'a real dose action is accepted');

select pg_temp.expect_rejected(
  'insert into dose_logs (id, schedule_id, user_id, scheduled_at, action) '
  'values (''00000000-0000-4000-8000-00000000000b'', ''00000000-0000-4000-8000-000000000001'', '
  '''11111111-1111-1111-1111-111111111111'', now(), ''eaten'')',
  'a dose action the app cannot read back is refused');

rollback;
