-- Adversarial test for consents and record_consent.
--
-- Run against a database with every migration applied, as a role that can
-- write to auth.users (the local `postgres` superuser, or `supabase db
-- connect`):
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/consents_test.sql
--
-- Everything runs inside a transaction that is rolled back. The things that
-- would be worst to get wrong: an unauthenticated write, a stranger or a
-- linked caregiver reading someone else's consents, a withdraw that still
-- looks granted, and an invalid purpose slipping through.

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

create or replace function pg_temp.expect_exception(stmt text, expected text, what text)
returns void
language plpgsql as $$
begin
  begin
    execute stmt;
  exception when others then
    if position(expected in sqlerrm) = 0 then
      raise exception 'FAILED: % — expected %, got %', what, expected, sqlerrm;
    end if;
    raise notice 'ok: % (%)', what, sqlerrm;
    return;
  end;
  raise exception 'FAILED: % — it was allowed', what;
end;
$$;

-- Currently granted: latest grant is in force and has not been withdrawn.
create or replace function pg_temp.currently_granted(who uuid, what text)
returns boolean
language sql
as $$
  select exists (
    select 1 from consents
     where user_id = who
       and purpose = what
       and granted_at is not null
       and withdrawn_at is null
  );
$$;

-- ---------------------------------------------------------------------------
-- unauthenticated cannot write
-- ---------------------------------------------------------------------------

reset role;
select set_config('request.jwt.claims', '{}', true);
select pg_temp.expect_exception(
  $q$select record_consent(
       'cloud_backup', true, '2026-08-20',
       'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
       '0.1.0+1')$q$,
  'not_authenticated',
  'unauthenticated cannot write'
);

-- ---------------------------------------------------------------------------
-- grant, own read, stranger cannot read
-- ---------------------------------------------------------------------------

select pg_temp.become(:'parent');
select record_consent(
  'cloud_backup',
  true,
  '2026-08-20',
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  '0.1.0+1'
);
select pg_temp.expect(
  (select count(*) from consents) = 1,
  'an owner can read their own consent row'
);
select pg_temp.expect(
  pg_temp.currently_granted(:'parent'::uuid, 'cloud_backup'),
  'a grant is currently granted'
);

select pg_temp.become(:'stranger');
select pg_temp.expect(
  (select count(*) from consents) = 0,
  'user A cannot select user B''s consents'
);

-- ---------------------------------------------------------------------------
-- a confirmed caregiver cannot read the patient's consents
-- ---------------------------------------------------------------------------

select pg_temp.become(:'parent');
select create_care_invite() as code \gset
select pg_temp.become(:'child');
select claim_care_invite(:'code')->>'id' as link_id \gset
select pg_temp.become(:'parent');
select confirm_care_link(:'link_id'::uuid);

select pg_temp.become(:'child');
select pg_temp.expect(
  (select count(*) from consents) = 0,
  'a caregiver on an active care_link cannot select the patient''s consents'
);
select pg_temp.expect(
  (select count(*) from consents where user_id = :'parent') = 0,
  'a caregiver cannot name the patient''s user_id to read consents either'
);

-- ---------------------------------------------------------------------------
-- grant then withdraw; re-grant stamps a new granted_at
-- ---------------------------------------------------------------------------

select pg_temp.become(:'parent');
select record_consent(
  'anthropic_parse',
  true,
  '2026-08-20',
  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  '0.1.0+1'
);
select pg_temp.expect(
  pg_temp.currently_granted(:'parent'::uuid, 'anthropic_parse'),
  'anthropic_parse is currently granted after the first grant'
);

select record_consent(
  'anthropic_parse',
  false,
  '2026-08-20',
  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  '0.1.0+1'
);
select pg_temp.expect(
  (select withdrawn_at is not null and granted_at is not null
     from consents
    where user_id = :'parent' and purpose = 'anthropic_parse'),
  'withdraw sets withdrawn_at and keeps the previous granted_at'
);
select pg_temp.expect(
  not pg_temp.currently_granted(:'parent'::uuid, 'anthropic_parse'),
  'withdrawn consent is not currently granted'
);

select record_consent(
  'anthropic_parse',
  true,
  '2026-08-20',
  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  '0.1.0+1'
);
select pg_temp.expect(
  (select withdrawn_at is null and granted_at is not null
     from consents
    where user_id = :'parent' and purpose = 'anthropic_parse'),
  're-grant sets granted_at and clears withdrawn_at'
);
select pg_temp.expect(
  pg_temp.currently_granted(:'parent'::uuid, 'anthropic_parse'),
  're-grant is currently granted'
);

-- ---------------------------------------------------------------------------
-- invalid purpose is refused; clients cannot insert directly
-- ---------------------------------------------------------------------------

select pg_temp.expect_exception(
  $q$select record_consent(
       'not_a_purpose', true, '2026-08-20',
       'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
       '0.1.0+1')$q$,
  'invalid_purpose',
  'invalid purpose is refused'
);

select pg_temp.expect_denied(
  format(
    $q$insert into consents (user_id, purpose, policy_version, consent_text_hash)
       values (%L, 'google_speech', '2026-08-20',
               'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd')$q$,
    :'parent'
  ),
  'clients cannot insert consents directly'
);

reset role;
rollback;
