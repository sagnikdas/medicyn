-- Adversarial test for the care-link access rule.
--
-- Run against a database with every migration applied, as a role that can
-- write to auth.users (the local `postgres` superuser, or `supabase db
-- connect`):
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/care_links_rls_test.sql
--
-- Everything runs inside a transaction that is rolled back, so it leaves no
-- users, links or medicines behind. The three test users are impersonated by
-- setting the JWT claims that `auth.uid()` reads.
--
-- It checks the things that would be worst to get wrong: that a caregiver
-- reaches exactly one account and no others, that a claimed-but-unconfirmed
-- invite grants nothing at all, and that revoking takes effect at once.

begin;

\set parent   '11111111-1111-1111-1111-111111111111'
\set child    '22222222-2222-2222-2222-222222222222'
\set stranger '33333333-3333-3333-3333-333333333333'

insert into auth.users (id, email) values
  (:'parent',   'parent@test.invalid'),
  (:'child',    'child@test.invalid'),
  (:'stranger', 'stranger@test.invalid');

insert into medicines (id, user_id, drug_name) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', :'parent',   'Metformin'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', :'stranger', 'Amlodipine');

-- Impersonate a user for subsequent statements.
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

-- Asserts that `stmt` is refused. Any error counts: the point is that the
-- database said no, not which particular way it said it.
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

-- Like expect_denied, but the message has to be the one the client maps.
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

-- ---------------------------------------------------------------------------
-- baseline: no link, no access
-- ---------------------------------------------------------------------------

select pg_temp.become(:'child');
select pg_temp.expect(
  (select count(*) from medicines) = 0,
  'an unlinked caregiver sees nothing at all'
);

select pg_temp.become(:'parent');
select pg_temp.expect(
  (select count(*) from medicines) = 1,
  'an owner sees their own medicine'
);
select pg_temp.expect(
  (select count(*) from medicines where user_id = :'stranger') = 0,
  'an owner cannot see a stranger''s medicine'
);

-- ---------------------------------------------------------------------------
-- issuing and claiming
-- ---------------------------------------------------------------------------

select create_care_invite() as code \gset
select pg_temp.expect(length(:'code') = 6, 'the invite code is six digits');

select pg_temp.become(:'child');
select pg_temp.expect(
  (select count(*) from care_links) = 0,
  'an outstanding invite is invisible to the person about to claim it'
);

select claim_care_invite(:'code') as link_id \gset
select set_config('test.link_id', :'link_id', false);

-- The critical one: possession of the code is not access.
select pg_temp.expect(
  (select count(*) from medicines) = 0,
  'claiming a code grants nothing until the parent confirms'
);

select pg_temp.expect_denied(
  format('select confirm_care_link(%L::uuid)', current_setting('test.link_id')),
  'a caregiver cannot confirm their own link'
);

-- ---------------------------------------------------------------------------
-- after confirmation
-- ---------------------------------------------------------------------------

select pg_temp.become(:'parent');
select confirm_care_link(current_setting('test.link_id')::uuid);

select pg_temp.become(:'child');
select pg_temp.expect(
  (select count(*) from medicines where user_id = :'parent') = 1,
  'a confirmed caregiver reads the parent''s medicines'
);
select pg_temp.expect(
  (select count(*) from medicines where user_id = :'stranger') = 0,
  'a confirmed caregiver reaches no other account'
);

insert into medicines (id, user_id, drug_name)
values ('cccccccc-cccc-cccc-cccc-cccccccccccc', :'parent', 'Atorvastatin');
select pg_temp.expect(
  (select count(*) from medicines where user_id = :'parent') = 2,
  'a caregiver can add a medicine for the parent'
);

select pg_temp.expect_denied(
  $q$insert into medicines (id, user_id, drug_name)
     values ('dddddddd-dddd-dddd-dddd-dddddddddddd',
             '33333333-3333-3333-3333-333333333333', 'Warfarin')$q$,
  'a caregiver cannot write onto an unlinked account'
);

-- Access is directional: being someone's patient grants nothing in return.
insert into medicines (id, user_id, drug_name)
values ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', :'child', 'Ibuprofen');

select pg_temp.become(:'parent');
select pg_temp.expect(
  (select count(*) from medicines where user_id = :'child') = 0,
  'the parent cannot read the caregiver''s own medicines'
);

-- ---------------------------------------------------------------------------
-- one-to-one, and bad codes
-- ---------------------------------------------------------------------------

select pg_temp.become(:'stranger');
select pg_temp.expect_denied(
  $q$select claim_care_invite('000000')$q$,
  'a wrong code is refused'
);

select pg_temp.become(:'parent');
select pg_temp.expect_denied(
  $q$select create_care_invite()$q$,
  'an already-linked parent cannot invite a second caregiver'
);

-- ---------------------------------------------------------------------------
-- revocation
-- ---------------------------------------------------------------------------

select revoke_care_link(current_setting('test.link_id')::uuid);

select pg_temp.become(:'child');
select pg_temp.expect(
  (select count(*) from medicines where user_id = :'parent') = 0,
  'revoking cuts the caregiver off at once'
);

select pg_temp.become(:'parent');
select create_care_invite() as code2 \gset
select pg_temp.expect(
  length(:'code2') = 6,
  'both sides are free to pair again after revoking'
);

-- ---------------------------------------------------------------------------
-- claimed-link expiry
-- ---------------------------------------------------------------------------
-- A claimed row is not a permanent ticket. Confirmation has to honour the
-- same 15-minute bound the UI promises, otherwise a claimed-but-unconfirmed
-- link sits forever.

select pg_temp.become(:'child');
select claim_care_invite(:'code2') as expired_link_id \gset
select set_config('test.expired_link_id', :'expired_link_id', false);

select pg_temp.expect(
  (select expires_at = now() + interval '15 minutes'
     from care_links
    where id = current_setting('test.expired_link_id')::uuid),
  'claiming stamps a fresh 15-minute confirmation window'
);

-- Age the claimed window into the past. Direct update: there is no write
-- policy on care_links, so this has to run as the table owner.
reset role;
update care_links
   set expires_at = now() - interval '1 minute'
 where id = current_setting('test.expired_link_id')::uuid;

select pg_temp.become(:'parent');
select pg_temp.expect_exception(
  format('select confirm_care_link(%L::uuid)', current_setting('test.expired_link_id')),
  'no_link_to_confirm',
  'a claimed link cannot be confirmed after its window expires'
);

-- Happy path on a fresh invite: claim then confirm while the window is open.
select revoke_care_link(current_setting('test.expired_link_id')::uuid);
select create_care_invite() as code3 \gset
select pg_temp.become(:'child');
select claim_care_invite(:'code3') as fresh_link_id \gset
select set_config('test.fresh_link_id', :'fresh_link_id', false);
select pg_temp.become(:'parent');
select confirm_care_link(current_setting('test.fresh_link_id')::uuid);
select pg_temp.expect(
  (select status = 'active' and expires_at is null
     from care_links
    where id = current_setting('test.fresh_link_id')::uuid),
  'confirming a still-valid claimed link succeeds and clears expiry'
);

reset role;
rollback;
