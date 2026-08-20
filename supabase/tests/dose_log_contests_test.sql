-- Adversarial test for dose_log_contests RLS.
--
-- Run against a database with every migration applied, as a role that can
-- write to auth.users (the local `postgres` superuser, or `supabase db
-- connect`):
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/dose_log_contests_test.sql
--
-- Everything runs inside a transaction that is rolled back. The things that
-- would be worst to get wrong: a caregiver fabricating a correction note on
-- the patient's log, a stranger reading the note, and the owner being unable
-- to write one.

begin;

\set parent   '11111111-1111-1111-1111-111111111111'
\set child    '22222222-2222-2222-2222-222222222222'
\set stranger '33333333-3333-3333-3333-333333333333'

insert into auth.users (id, email) values
  (:'parent',   'parent@test.invalid'),
  (:'child',    'child@test.invalid'),
  (:'stranger', 'stranger@test.invalid');

insert into profiles (user_id, display_name) values
  (:'parent',   'Asha'),
  (:'child',    'Priya'),
  (:'stranger', 'Ravi');

create or replace function pg_temp.become(who uuid) returns void
language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', who::text, 'role', 'authenticated')::text,
    true
  );
end;
$$;

create or replace function pg_temp.expect(ok boolean, what text) returns void
language plpgsql as $$
begin
  if not ok then
    raise exception 'FAILED: %', what;
  end if;
  raise notice 'ok: %', what;
end;
$$;

create or replace function pg_temp.expect_denied(stmt text, what text) returns void
language plpgsql as $$
begin
  begin
    execute stmt;
  exception when others then
    raise notice 'ok: % (%)', what, sqlstate;
    return;
  end;
  raise exception 'FAILED: % — it was allowed', what;
end;
$$;

-- ---------------------------------------------------------------------------
-- owner writes a log, then a contest note
-- ---------------------------------------------------------------------------

select pg_temp.become(:'parent');

insert into medicines (id, user_id, drug_name)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', :'parent', 'Metformin');

insert into schedules (id, medicine_id, user_id, frequency_type, times)
values ('ffffffff-ffff-ffff-ffff-ffffffffffff',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', :'parent', 'daily', '["09:00"]'::jsonb);

insert into dose_logs (id, schedule_id, user_id, scheduled_at, action)
values ('12121212-1212-1212-1212-121212121212',
        'ffffffff-ffff-ffff-ffff-ffffffffffff', :'parent', now(), 'missed');

insert into dose_log_contests (dose_log_id, user_id, note)
values ('12121212-1212-1212-1212-121212121212', :'parent', 'I did take this');

select pg_temp.expect(
  (select count(*) from dose_log_contests) = 1,
  'an owner can insert a contest note on their own log'
);
select pg_temp.expect(
  (select note from dose_log_contests
    where dose_log_id = '12121212-1212-1212-1212-121212121212')
    = 'I did take this',
  'the owner can read the note back'
);
select pg_temp.expect(
  (select action from dose_logs
    where id = '12121212-1212-1212-1212-121212121212') = 'missed',
  'inserting a contest note does not change dose_logs.action'
);

-- The payload's user_id is ignored; the parent log is the owner.
insert into dose_log_contests (dose_log_id, user_id, note)
values ('12121212-1212-1212-1212-121212121212', :'child', 'replaced')
on conflict (dose_log_id) do update set note = excluded.note, updated_at = now();

select pg_temp.expect(
  (select user_id from dose_log_contests
    where dose_log_id = '12121212-1212-1212-1212-121212121212')
    = :'parent'::uuid,
  'user_id stays the parent even when the payload names someone else'
);

-- ---------------------------------------------------------------------------
-- stranger cannot read
-- ---------------------------------------------------------------------------

select pg_temp.become(:'stranger');
select pg_temp.expect(
  (select count(*) from dose_log_contests) = 0,
  'a stranger cannot read the patient''s contest note'
);

-- ---------------------------------------------------------------------------
-- active caregiver can read, cannot insert or update
-- ---------------------------------------------------------------------------

select pg_temp.become(:'parent');
select create_care_invite() as code \gset
select pg_temp.become(:'child');
select claim_care_invite(:'code')->>'id' as link_id \gset
select pg_temp.become(:'parent');
select confirm_care_link(:'link_id'::uuid);

select pg_temp.become(:'child');
select pg_temp.expect(
  (select count(*) from dose_log_contests) = 1,
  'a caregiver with an active link can read the patient''s contest note'
);
select pg_temp.expect(
  (select note from dose_log_contests
    where dose_log_id = '12121212-1212-1212-1212-121212121212')
    = 'replaced',
  'the caregiver reads the same note the patient wrote'
);

select pg_temp.expect_denied(
  $q$insert into dose_log_contests (dose_log_id, user_id, note)
     values ('12121212-1212-1212-1212-121212121212',
             '11111111-1111-1111-1111-111111111111', 'forged')$q$,
  'a caregiver cannot insert a contest note on the patient''s log'
);

-- A second log so the caregiver's insert is not just a PK collision.
select pg_temp.become(:'parent');
insert into dose_logs (id, schedule_id, user_id, scheduled_at, action)
values ('13131313-1313-1313-1313-131313131313',
        'ffffffff-ffff-ffff-ffff-ffffffffffff', :'parent', now(), 'taken');

select pg_temp.become(:'child');
select pg_temp.expect_denied(
  $q$insert into dose_log_contests (dose_log_id, user_id, note)
     values ('13131313-1313-1313-1313-131313131313',
             '11111111-1111-1111-1111-111111111111', 'forged on a fresh log')$q$,
  'a caregiver cannot insert a contest note on another of the patient''s logs'
);
select pg_temp.expect_denied(
  $q$insert into dose_log_contests (dose_log_id, user_id, note)
     values ('13131313-1313-1313-1313-131313131313',
             '22222222-2222-2222-2222-222222222222', 'forged as myself')$q$,
  'a caregiver cannot attach a contest note using their own user_id either'
);

update dose_log_contests
   set note = 'forged update'
 where dose_log_id = '12121212-1212-1212-1212-121212121212';
select pg_temp.expect(
  (select note from dose_log_contests
    where dose_log_id = '12121212-1212-1212-1212-121212121212')
    = 'replaced',
  'a caregiver cannot update the patient''s contest note'
);

reset role;
rollback;
