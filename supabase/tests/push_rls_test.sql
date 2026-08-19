-- Adversarial test for the push tables.
--
-- Run against a database with every migration applied, as a role that can
-- write to auth.users (the local `postgres` superuser, or `supabase db
-- connect`):
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/push_rls_test.sql
--
-- Everything runs inside a transaction that is rolled back. The two facts
-- worth being certain of:
--
--   * A device token is never readable by anyone but its owner — not even by
--     a confirmed caregiver, who can read everything else about the person.
--     A token is a capability to ring a phone, not information about health.
--   * Registering a token that already exists moves it to the caller. An FCM
--     token belongs to an app *install*: if signing in as a second account on
--     one phone left the row pointing at the first, that phone would keep
--     receiving alerts addressed to whoever handed it over.

begin;

\set parent   '11111111-1111-1111-1111-111111111111'
\set child    '22222222-2222-2222-2222-222222222222'
\set stranger '33333333-3333-3333-3333-333333333333'

insert into auth.users (id, email) values
  (:'parent',   'parent@test.invalid'),
  (:'child',    'child@test.invalid'),
  (:'stranger', 'stranger@test.invalid');

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
-- registration
-- ---------------------------------------------------------------------------

select pg_temp.become(:'parent');
select register_device_token('token-parent-phone', 'android');
select pg_temp.expect(
  (select count(*) from device_tokens where token = 'token-parent-phone'
     and user_id = :'parent') = 1,
  'registering a token records it against the caller'
);

select pg_temp.expect_denied(
  $q$select register_device_token('token-bad-platform', 'windows')$q$,
  'an unknown platform is refused'
);

-- Registration is only reachable through the function; there is no insert
-- policy at all, so even an honest self-addressed insert is refused.
select pg_temp.expect_denied(
  $q$insert into device_tokens (token, user_id, platform)
     values ('token-direct', '11111111-1111-1111-1111-111111111111', 'android')$q$,
  'a direct insert is refused even for your own account'
);
select pg_temp.expect_denied(
  $q$insert into device_tokens (token, user_id, platform)
     values ('token-forged', '22222222-2222-2222-2222-222222222222', 'android')$q$,
  'a direct insert onto someone else''s account is refused'
);

-- The shared-phone case. Same install, second Google account.
select pg_temp.become(:'child');
select register_device_token('token-parent-phone', 'android');
select pg_temp.become(:'parent');
select pg_temp.expect(
  (select count(*) from device_tokens where token = 'token-parent-phone') = 0,
  'a re-registered token stops being addressed to the previous account'
);
select pg_temp.become(:'child');
select pg_temp.expect(
  (select count(*) from device_tokens where token = 'token-parent-phone'
     and user_id = :'child') = 1,
  'a re-registered token moves to the account that registered it'
);

-- ---------------------------------------------------------------------------
-- visibility, including across a confirmed link
-- ---------------------------------------------------------------------------

select pg_temp.become(:'parent');
select register_device_token('token-parent-2', 'android');

select pg_temp.become(:'stranger');
select pg_temp.expect(
  (select count(*) from device_tokens) = 0,
  'an unrelated account sees no tokens at all'
);

-- Establish a real, confirmed link, then check it changes nothing here.
select pg_temp.become(:'parent');
select create_care_invite() as code \gset
select pg_temp.become(:'child');
select claim_care_invite(:'code') as link_id \gset
select set_config('test.link_id', :'link_id', false);
select pg_temp.become(:'parent');
select confirm_care_link(current_setting('test.link_id')::uuid);

select pg_temp.become(:'child');
select pg_temp.expect(
  (select count(*) from device_tokens where user_id = :'parent') = 0,
  'a confirmed caregiver cannot read the patient''s device tokens'
);
select pg_temp.become(:'parent');
select pg_temp.expect(
  (select count(*) from device_tokens where user_id = :'child') = 0,
  'the patient cannot read the caregiver''s device tokens either'
);

-- ---------------------------------------------------------------------------
-- sign-out
-- ---------------------------------------------------------------------------

select pg_temp.expect(
  (select count(*) from device_tokens where user_id = :'parent') = 1,
  'the patient still holds their own token'
);
delete from device_tokens where token = 'token-parent-2';
select pg_temp.expect(
  (select count(*) from device_tokens where user_id = :'parent') = 0,
  'signing out can delete your own token'
);

select pg_temp.become(:'child');
select register_device_token('token-child-phone', 'android');
select pg_temp.become(:'parent');
delete from device_tokens where token = 'token-child-phone';
select pg_temp.become(:'child');
select pg_temp.expect(
  (select count(*) from device_tokens where token = 'token-child-phone') = 1,
  'nobody can delete someone else''s token'
);

-- ---------------------------------------------------------------------------
-- care_alerts
-- ---------------------------------------------------------------------------
-- Written only by the edge function under the service role, so the tests here
-- are about who may *read* one, plus that nothing can forge one.

select pg_temp.become(:'parent');
select pg_temp.expect_denied(
  format(
    $q$insert into care_alerts (link_id, recipient_id, kind)
       values (%L::uuid, '22222222-2222-2222-2222-222222222222', 'missed_dose')$q$,
    current_setting('test.link_id')
  ),
  'a client cannot write a care alert'
);

-- Insert one the way the function does: as the service role, which bypasses
-- RLS entirely.
reset role;
insert into care_alerts (link_id, recipient_id, kind, delivered_count)
values (current_setting('test.link_id')::uuid, :'child', 'missed_dose', 1);

select pg_temp.become(:'child');
select pg_temp.expect(
  (select count(*) from care_alerts) = 1,
  'the caregiver reads the alert that was sent to them'
);
select pg_temp.become(:'parent');
select pg_temp.expect(
  (select count(*) from care_alerts) = 1,
  'the patient reads what was said about them — the symmetry promise'
);
select pg_temp.become(:'stranger');
select pg_temp.expect(
  (select count(*) from care_alerts) = 0,
  'nobody outside the link sees the alert'
);

-- The de-duplication that stops two devices announcing one missed dose twice.
reset role;
insert into medicines (id, user_id, drug_name)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', :'parent', 'Metformin');
insert into schedules (id, medicine_id, user_id, frequency_type, times)
values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', :'parent', 'daily', '["09:00"]'::jsonb);
insert into dose_logs (id, schedule_id, user_id, scheduled_at, action)
values ('cccccccc-cccc-cccc-cccc-cccccccccccc',
        'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', :'parent', now() - interval '1 hour', 'missed');

insert into care_alerts (link_id, recipient_id, kind, dose_log_id)
values (current_setting('test.link_id')::uuid, :'child', 'missed_dose',
        'cccccccc-cccc-cccc-cccc-cccccccccccc');

select pg_temp.expect_denied(
  format(
    $q$insert into care_alerts (link_id, recipient_id, kind, dose_log_id)
       values (%L::uuid, '22222222-2222-2222-2222-222222222222', 'missed_dose',
               'cccccccc-cccc-cccc-cccc-cccccccccccc')$q$,
    current_setting('test.link_id')
  ),
  'the same missed dose cannot be announced twice on one link'
);

-- Two `data_changed` rows must still be allowed: nulls are distinct in the
-- unique index, which is the reason it is total rather than partial.
insert into care_alerts (link_id, recipient_id, kind)
values (current_setting('test.link_id')::uuid, :'parent', 'data_changed');
insert into care_alerts (link_id, recipient_id, kind)
values (current_setting('test.link_id')::uuid, :'parent', 'data_changed');
select pg_temp.expect(
  (select count(*) from care_alerts where kind = 'data_changed') = 2,
  'repeated silent pushes are each recorded'
);

reset role;
rollback;
