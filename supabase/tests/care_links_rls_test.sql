-- Adversarial test for the care-link access rule.
--
-- Run against a database with every migration applied, as a role that can
-- write to auth.users (the local `postgres` superuser, or `supabase db
-- connect`):
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/care_links_rls_test.sql
--
-- Everything runs inside a transaction that is rolled back, so it leaves no
-- users, links or medicines behind. The test users are impersonated by
-- setting the JWT claims that `auth.uid()` reads.
--
-- It checks the things that would be worst to get wrong: that a caregiver
-- reaches exactly one account and no others, that a claimed-but-unconfirmed
-- invite grants nothing at all, and that revoking takes effect at once.

begin;

\set parent   '11111111-1111-1111-1111-111111111111'
\set child    '22222222-2222-2222-2222-222222222222'
\set stranger '33333333-3333-3333-3333-333333333333'
\set guesser  '44444444-4444-4444-4444-444444444444'

insert into auth.users (id, email) values
  (:'parent',   'parent@test.invalid'),
  (:'child',    'child@test.invalid'),
  (:'stranger', 'stranger@test.invalid'),
  (:'guesser',  'guesser@test.invalid');

insert into profiles (user_id, display_name) values
  (:'parent',   'Asha'),
  (:'child',    'Priya'),
  (:'stranger', 'Ravi'),
  (:'guesser',  'Dev');

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

-- Repeats [stmt] [n] times, each of which must fail with [expected].
create or replace function pg_temp.expect_n_failures(n int, stmt text, expected text, what text)
returns void
language plpgsql as $$
declare
  i int;
begin
  for i in 1..n loop
    begin
      execute stmt;
      raise exception 'FAILED: % — attempt % was allowed', what, i;
    exception
      when others then
        if sqlerrm like 'FAILED:%' then
          raise;
        end if;
        if position(expected in sqlerrm) = 0 then
          raise exception 'FAILED: % — attempt % expected %, got %',
            what, i, expected, sqlerrm;
        end if;
    end;
  end loop;
  raise notice 'ok: % (% times)', what, n;
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
select pg_temp.expect(length(:'code') = 8, 'the invite code is eight digits');

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

-- Identity at confirmation: the patient may name the claimant through the
-- dedicated RPC, and nobody else may. `profiles_read` stays closed while the
-- link is only claimed — that was the original hole, and it must stay shut.
select pg_temp.expect(
  (select count(*) from claimed_care_link_claimant(current_setting('test.link_id')::uuid)) = 0,
  'a caregiver cannot read claimant identity'
);
select pg_temp.expect(
  (select count(*) from profiles where user_id = :'parent') = 0,
  'a claimed caregiver still cannot read the patient''s profile'
);

select pg_temp.become(:'stranger');
select pg_temp.expect(
  (select count(*) from claimed_care_link_claimant(current_setting('test.link_id')::uuid)) = 0,
  'a stranger cannot read claimant identity'
);

select pg_temp.become(:'parent');
select pg_temp.expect(
  (select count(*) from profiles where user_id = :'child') = 0,
  'claimed profiles_read is still empty for the caregiver'
);
select pg_temp.expect(
  (select count(*) from claimed_care_link_claimant(current_setting('test.link_id')::uuid)) = 1,
  'the claimed patient can call the identity rpc'
);
select pg_temp.expect(
  (select email from claimed_care_link_claimant(current_setting('test.link_id')::uuid))
    = 'child@test.invalid',
  'the claimed patient sees the claimant''s email'
);
select pg_temp.expect(
  (select display_name from claimed_care_link_claimant(current_setting('test.link_id')::uuid))
    = 'Priya',
  'the claimed patient sees the claimant''s display name'
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
-- profiles, can_access_user_data, one-live-link
-- ---------------------------------------------------------------------------
-- The confirm prompt's reverse read (patient → caregiver) is a separate
-- policy arm from can_access_user_data. F-6 turned that arm on; these
-- assertions are what would have caught a claimed-state leak and what
-- stops it regressing. The unique indexes are the race backstop the RPCs
-- are not allowed to be the only copy of.

select pg_temp.become(:'parent');
select pg_temp.expect(
  (select display_name from profiles where user_id = :'parent') = 'Asha',
  'a user can read their own profile'
);
select pg_temp.expect(
  (select display_name from profiles where user_id = :'child') = 'Priya',
  'an active patient can read the caregiver''s profile'
);
select pg_temp.expect(
  can_access_user_data(:'parent'::uuid),
  'can_access_user_data is true for the caller''s own id'
);
select pg_temp.expect(
  not can_access_user_data(:'child'::uuid),
  'can_access_user_data does not open the caregiver''s medical rows to the patient'
);
select pg_temp.expect(
  not coalesce(can_access_user_data(null), false),
  'can_access_user_data(null) is not true'
);

select pg_temp.become(:'child');
select pg_temp.expect(
  (select display_name from profiles where user_id = :'parent') = 'Asha',
  'an active caregiver can read the patient''s profile'
);
select pg_temp.expect(
  can_access_user_data(:'parent'::uuid),
  'an active caregiver can_access_user_data of the patient'
);
update profiles set display_name = 'Hijacked' where user_id = :'parent';
select pg_temp.expect(
  (select display_name from profiles where user_id = :'parent') = 'Asha',
  'a caregiver cannot rename the patient'
);

select pg_temp.become(:'stranger');
select pg_temp.expect(
  (select count(*) from profiles where user_id = :'parent') = 0,
  'a stranger cannot read the patient''s profile'
);
select pg_temp.expect(
  (select count(*) from profiles where user_id = :'child') = 0,
  'a stranger cannot read the caregiver''s profile'
);

-- auth.uid() is null when the JWT names no user. RLS treats a null
-- predicate as false; this asserts the function itself, not a table walk.
select pg_temp.become(:'parent');
select set_config('request.jwt.claims', '{}', true);
select pg_temp.expect(
  not coalesce(can_access_user_data(:'parent'::uuid), false),
  'can_access_user_data is false when auth.uid() is null'
);
select pg_temp.become(:'parent');

reset role;
select pg_temp.expect_denied(
  format(
    $q$insert into care_links (id, patient_id, caregiver_id, status)
       values ('88888888-8888-8888-8888-888888888888', %L, %L, 'active')$q$,
    :'parent', :'stranger'
  ),
  'a second live link for the same patient is refused'
);
select pg_temp.expect_denied(
  format(
    $q$insert into care_links (id, patient_id, caregiver_id, status)
       values ('99999999-9999-9999-9999-999999999999', %L, %L, 'active')$q$,
    :'stranger', :'child'
  ),
  'a second live link for the same caregiver is refused'
);
select pg_temp.become(:'parent');

-- ---------------------------------------------------------------------------
-- dose_logs: the patient's device is the only writer
-- ---------------------------------------------------------------------------
-- The feed is readable by both sides of an active link. A caregiver writing
-- a 'taken' row for the parent is the thing this policy exists to refuse.

insert into schedules (id, medicine_id, user_id, frequency_type, times)
values ('ffffffff-ffff-ffff-ffff-ffffffffffff',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', :'parent', 'daily', '["09:00"]'::jsonb);

insert into dose_logs (id, schedule_id, user_id, scheduled_at, action, recorded_by)
values ('12121212-1212-1212-1212-121212121212',
        'ffffffff-ffff-ffff-ffff-ffffffffffff', :'parent', now(), 'taken', :'child');
select pg_temp.expect(
  (select count(*) from dose_logs where user_id = :'parent') = 1,
  'the patient can record a dose log'
);
select pg_temp.expect(
  (select recorded_by from dose_logs where id = '12121212-1212-1212-1212-121212121212')
    = :'parent'::uuid,
  'recorded_by is the caller, even when the payload names someone else'
);

select pg_temp.become(:'child');
select pg_temp.expect(
  (select count(*) from dose_logs where user_id = :'parent') = 1,
  'a confirmed caregiver can read the parent''s dose logs'
);
select pg_temp.expect_denied(
  $q$insert into dose_logs (id, schedule_id, user_id, scheduled_at, action)
     values ('13131313-1313-1313-1313-131313131313',
             'ffffffff-ffff-ffff-ffff-ffffffffffff',
             '11111111-1111-1111-1111-111111111111', now(), 'taken')$q$,
  'a caregiver cannot write a dose log for the parent'
);

-- UPDATE/DELETE under RLS that match no rows succeed with a row count of
-- zero rather than raising, so "was it refused" is "did the row survive".
update dose_logs set action = 'missed' where user_id = :'parent';
select pg_temp.expect(
  (select action from dose_logs where id = '12121212-1212-1212-1212-121212121212') = 'taken',
  'a caregiver cannot update the parent''s dose logs'
);
delete from dose_logs where user_id = :'parent';
select pg_temp.expect(
  (select count(*) from dose_logs where user_id = :'parent') = 1,
  'a caregiver cannot delete the parent''s dose logs'
);

-- Caregiver writes to medicines/schedules are allowed — that is Phase 2 —
-- but deletion is the patient's alone. Deactivation (active = false) is an
-- update, not a delete, and is still permitted; the app simply does not
-- offer it on the caregiver screen.
insert into schedules (id, medicine_id, user_id, frequency_type, times)
values ('abababab-abab-abab-abab-abababababab',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', :'parent', 'daily', '["21:00"]'::jsonb);
select pg_temp.expect(
  (select count(*) from schedules where user_id = :'parent') = 2,
  'a caregiver can still add a schedule for the parent'
);

update medicines set notes = 'from Priya' where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
select pg_temp.expect(
  (select notes from medicines where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') = 'from Priya',
  'a caregiver can edit the parent''s medicine'
);
select pg_temp.expect(
  (select updated_by from medicines where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
    = :'child'::uuid,
  'updated_by is the caller''s JWT, not a client-supplied id'
);
select pg_temp.expect(
  (select count(*) from medicine_edits where medicine_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') >= 1,
  'an edit writes a history row'
);
select pg_temp.expect(
  exists (
    select 1 from medicine_edits
     where medicine_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
       and actor_id = :'child'::uuid
  ),
  'the history row names the caregiver'
);

insert into medicines (id, user_id, drug_name, updated_by)
values ('abab0000-aaaa-4aaa-8aaa-aaaaaaaaaaaa', :'parent', 'Telmisartan', :'parent');
select pg_temp.expect(
  (select updated_by from medicines where id = 'abab0000-aaaa-4aaa-8aaa-aaaaaaaaaaaa')
    = :'child'::uuid,
  'a forged updated_by is overwritten with the caller'
);

delete from medicines where user_id = :'parent';
select pg_temp.expect(
  (select count(*) from medicines where user_id = :'parent') = 3,
  'a caregiver cannot delete the parent''s medicines'
);
delete from schedules where user_id = :'parent';
select pg_temp.expect(
  (select count(*) from schedules where user_id = :'parent') = 2,
  'a caregiver cannot delete the parent''s schedules'
);

select pg_temp.expect_exception(
  format(
    $q$update medicines set user_id = %L where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$q$,
    :'child'
  ),
  'cannot_reassign_owner',
  'a caregiver cannot move the parent''s medicine onto their own account'
);

update profiles set notifications_allowed = false where user_id = :'parent';
select pg_temp.expect(
  (select notifications_allowed from profiles where user_id = :'parent') is null,
  'setup-health stays unread until the owner reports it'
);

select pg_temp.become(:'parent');
update profiles set
  notifications_allowed = true,
  exact_alarms_allowed = true,
  battery_exemption = false,
  armed_alarm_count = 2,
  health_checked_at = now()
where user_id = :'parent';
select pg_temp.expect(
  (select battery_exemption from profiles where user_id = :'parent') = false,
  'the patient can write their own setup health'
);
select pg_temp.become(:'child');
select pg_temp.expect(
  (select battery_exemption from profiles where user_id = :'parent') = false,
  'a confirmed caregiver can read the parent''s setup health'
);

-- ---------------------------------------------------------------------------
-- one-to-one, and bad codes
-- ---------------------------------------------------------------------------

select pg_temp.become(:'stranger');
select pg_temp.expect_denied(
  $q$select claim_care_invite('00000000')$q$,
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
select pg_temp.expect(
  (select count(*) from profiles where user_id = :'parent') = 0,
  'revoking cuts the caregiver off the patient''s profile'
);

select pg_temp.become(:'parent');
select pg_temp.expect(
  (select count(*) from profiles where user_id = :'child') = 0,
  'revoking cuts the patient off the caregiver''s profile'
);
select create_care_invite() as code2 \gset
select pg_temp.expect(
  length(:'code2') = 8,
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

-- ---------------------------------------------------------------------------
-- claim rate limit
-- ---------------------------------------------------------------------------
-- Every attempt is counted, including failures, so the counter cannot tell
-- a guesser whether a code exists. The 11th call in 15 minutes is refused
-- before the code is even looked up.

select pg_temp.become(:'guesser');
select pg_temp.expect_n_failures(
  10,
  $q$select claim_care_invite('00000000')$q$,
  'invalid_or_expired_code',
  'the first ten wrong claims in a window still look like a bad code'
);
select pg_temp.expect_exception(
  $q$select claim_care_invite('00000000')$q$,
  'too_many_attempts',
  'an 11th claim attempt in 15 minutes is refused'
);
select pg_temp.expect(
  (select count(*) from care_invite_claim_attempts) = 0,
  'clients cannot read the claim-attempt ledger'
);

reset role;
rollback;

-- Attempt rows are written on a second connection so a failed claim still
-- counts. ROLLBACK above does not remove them; sweep so a re-run on the
-- same database does not inherit the cap.
delete from care_invite_claim_attempts;
