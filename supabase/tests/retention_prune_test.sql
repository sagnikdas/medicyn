-- Retention prune: expired rows go, live ones stay.
--
-- Run against a database with every migration applied, as a role that can
-- write to auth.users (the local `postgres` superuser, or `supabase db
-- connect`):
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/retention_prune_test.sql
--
-- Everything runs inside a transaction that is rolled back. The prune
-- runs as the table owner so RLS is not in the way — that is how cron
-- and the operator call it.

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

insert into medicines (id, user_id, drug_name)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', :'parent', 'Metformin');

insert into schedules (id, medicine_id, user_id, frequency_type, times)
values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', :'parent',
        'daily', '["09:00"]'::jsonb);

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

-- ---------------------------------------------------------------------------
-- seed
-- ---------------------------------------------------------------------------

insert into dose_logs (id, schedule_id, user_id, scheduled_at, action, logged_at)
values
  ('11111111-aaaa-4aaa-8aaa-111111111111',
   'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', :'parent',
   now() - interval '25 months', 'taken', now() - interval '25 months'),
  ('22222222-aaaa-4aaa-8aaa-222222222222',
   'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', :'parent',
   now() - interval '7 days', 'taken', now() - interval '7 days');

-- Revoked 13 months ago (must go). Active and old (must stay). Pending and
-- old on another patient (must stay). A second revoked row with a null
-- revoked_at still ages out through accepted_at.
insert into care_links (
  id, patient_id, caregiver_id, status,
  created_at, accepted_at, revoked_at
) values
  ('cccc1111-cccc-4ccc-8ccc-cccccccccccc',
   :'parent', :'child', 'revoked',
   now() - interval '14 months', now() - interval '14 months',
   now() - interval '13 months'),
  ('cccc2222-cccc-4ccc-8ccc-cccccccccccc',
   :'parent', :'child', 'revoked',
   now() - interval '14 months', now() - interval '13 months',
   null),
  ('cccc3333-cccc-4ccc-8ccc-cccccccccccc',
   :'parent', :'child', 'active',
   now() - interval '14 months', now() - interval '14 months',
   null);

insert into care_links (
  id, patient_id, status, invite_code, created_at
) values
  ('cccc4444-cccc-4ccc-8ccc-cccccccccccc',
   :'stranger', 'pending', 'ABCD1234', now() - interval '13 months');

insert into care_alerts (id, link_id, recipient_id, kind, sent_at)
values
  ('dddd1111-dddd-4ddd-8ddd-dddddddddddd',
   'cccc3333-cccc-4ccc-8ccc-cccccccccccc', :'child', 'data_changed',
   now() - interval '13 months'),
  ('dddd2222-dddd-4ddd-8ddd-dddddddddddd',
   'cccc3333-cccc-4ccc-8ccc-cccccccccccc', :'child', 'data_changed',
   now() - interval '2 days');

insert into device_tokens (token, user_id, platform, refreshed_at)
values
  ('token-stale', :'parent', 'android', now() - interval '91 days'),
  ('token-fresh', :'parent', 'android', now() - interval '1 day');

-- Clients must not be able to run this. Default privileges would otherwise
-- grant execute to authenticated.
select pg_temp.expect(
  has_function_privilege('authenticated', 'public.prune_expired_data()', 'execute') is false,
  'authenticated is not granted execute on prune_expired_data'
);

select pg_temp.become(:'parent');
select pg_temp.expect_denied(
  $q$select public.prune_expired_data()$q$,
  'an authenticated session cannot call prune_expired_data'
);
reset role;

-- ---------------------------------------------------------------------------
-- prune, then assert
-- ---------------------------------------------------------------------------

create temp table prune_result as
  select * from public.prune_expired_data();

select pg_temp.expect(
  (select deleted_count from prune_result where entity = 'dose_logs') = 1,
  'exactly one expired dose log is deleted'
);
select pg_temp.expect(
  (select deleted_count from prune_result where entity = 'care_alerts') = 1,
  'exactly one expired care alert is deleted'
);
select pg_temp.expect(
  (select deleted_count from prune_result where entity = 'care_links') = 2,
  'both aged-out revoked care links are deleted'
);
select pg_temp.expect(
  (select deleted_count from prune_result where entity = 'device_tokens') = 1,
  'exactly one stale device token is deleted'
);

select pg_temp.expect(
  (select count(*) from dose_logs) = 1,
  'a dose log from last week is kept'
);
select pg_temp.expect(
  (select id from dose_logs) = '22222222-aaaa-4aaa-8aaa-222222222222'::uuid,
  'the kept dose log is the recent one'
);

select pg_temp.expect(
  (select count(*) from care_alerts) = 1,
  'a recent care alert is kept'
);
select pg_temp.expect(
  (select id from care_alerts) = 'dddd2222-dddd-4ddd-8ddd-dddddddddddd'::uuid,
  'the kept care alert is the recent one'
);

select pg_temp.expect(
  (select count(*) from care_links where status = 'active') = 1,
  'an active care link is kept even when it is old'
);
select pg_temp.expect(
  (select count(*) from care_links where status = 'pending') = 1,
  'a pending care link is not pruned'
);
select pg_temp.expect(
  (select count(*) from care_links where status = 'revoked') = 0,
  'no revoked care link older than 12 months remains'
);

select pg_temp.expect(
  (select count(*) from device_tokens) = 1,
  'a recently refreshed device token is kept'
);
select pg_temp.expect(
  (select token from device_tokens) = 'token-fresh',
  'the kept device token is the one refreshed yesterday'
);

select pg_temp.expect(
  (select count(*) from medicines) = 1
  and (select count(*) from schedules) = 1
  and (select count(*) from profiles) = 3,
  'medicines, schedules and profiles are not pruned'
);

rollback;
