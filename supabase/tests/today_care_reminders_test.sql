-- Run after local_harness.sql and the today_care_reminders migration, or
-- against a Supabase test database. All fixtures are rolled back.
begin;

insert into auth.users(id, email) values
  ('11111111-1111-1111-1111-111111111111', 'care-owner@test.invalid'),
  ('22222222-2222-2222-2222-222222222222', 'care-stranger@test.invalid');

create function pg_temp.become(who uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', who)::text, true);
end;
$$;
create function pg_temp.expect(ok boolean, what text) returns void language plpgsql as $$
begin
  if ok is distinct from true then raise exception 'FAILED: %', what; end if;
  raise notice 'ok: %', what;
end;
$$;
create function pg_temp.denied(stmt text, what text) returns void language plpgsql as $$
begin
  begin
    execute stmt;
  exception when insufficient_privilege or check_violation then
    raise notice 'ok: %', what;
    return;
  end;
  raise exception 'FAILED: %', what;
end;
$$;

select pg_temp.become('11111111-1111-1111-1111-111111111111');
insert into public.today_care_reminders(user_id, title, kind, scheduled_at, updated_at)
select '11111111-1111-1111-1111-111111111111', kind, kind,
       '2026-09-10 10:00:00Z', '2026-09-06 10:00:00Z'
from unnest(array['test', 'scan', 'therapy', 'appointment', 'other']) kind;
select pg_temp.expect((select count(*) = 5 from today_care_reminders), 'owner can create and read all five categories');

update today_care_reminders set title = 'Updated scan', completed = true,
  updated_at = '2026-09-06 11:00:00Z' where kind = 'scan';
select pg_temp.expect((select title = 'Updated scan' and completed from today_care_reminders where kind = 'scan'), 'owner edits and completes an entry');

update today_care_reminders set deleted = true, updated_at = '2026-09-06 12:00:00Z' where kind = 'scan';
-- Simulate an offline client's stale upsert after the delete reached Supabase.
insert into today_care_reminders(id, user_id, title, kind, scheduled_at, updated_at, deleted)
select id, user_id, 'Stale scan', kind, scheduled_at, '2026-09-06 11:30:00Z', false
from today_care_reminders where kind = 'scan'
on conflict(id) do update set title = excluded.title, deleted = excluded.deleted, updated_at = excluded.updated_at;
select pg_temp.expect((select deleted and title = 'Updated scan' from today_care_reminders where kind = 'scan'), 'stale upsert cannot resurrect a deleted entry');

update today_care_reminders set deleted = false, completed = false, updated_at = '2026-09-06 13:00:00Z' where kind = 'scan';
select pg_temp.expect((select not deleted and not completed from today_care_reminders where kind = 'scan'), 'a newer undo restores the entry');

select pg_temp.denied($q$update today_care_reminders set user_id = '22222222-2222-2222-2222-222222222222', updated_at = now()$q$, 'owner cannot transfer entries into another account');
select pg_temp.denied($q$insert into today_care_reminders(user_id,title,kind,scheduled_at) values('11111111-1111-1111-1111-111111111111','bad','medicine',now())$q$, 'invalid category is rejected');
select pg_temp.denied($q$insert into today_care_reminders(user_id,title,kind,scheduled_at,reminder_minutes) values('11111111-1111-1111-1111-111111111111','bad','other',now(),-1)$q$, 'negative reminder offset is rejected');

select pg_temp.become('22222222-2222-2222-2222-222222222222');
select pg_temp.expect((select count(*) = 0 from today_care_reminders), 'another account cannot read entries');
select pg_temp.denied($q$insert into today_care_reminders(user_id,title,kind,scheduled_at) values('11111111-1111-1111-1111-111111111111','forged','other',now())$q$, 'another account cannot create entries for the owner');
update today_care_reminders set title = 'forged', updated_at = now();
delete from today_care_reminders;

select pg_temp.become(null);
select pg_temp.expect((select count(*) = 0 from today_care_reminders), 'a missing JWT cannot read entries');
select pg_temp.denied($q$insert into today_care_reminders(user_id,title,kind,scheduled_at) values('11111111-1111-1111-1111-111111111111','forged','other',now())$q$, 'a missing JWT cannot create entries');

select pg_temp.become('11111111-1111-1111-1111-111111111111');
select pg_temp.expect((select count(*) = 5 and bool_and(title <> 'forged') from today_care_reminders), 'another account cannot update or delete entries');
delete from today_care_reminders where kind = 'other';
select pg_temp.expect((select count(*) = 4 from today_care_reminders), 'owner can hard-delete their own data');

reset role;
delete from auth.users where id = '11111111-1111-1111-1111-111111111111';
select pg_temp.expect((select count(*) = 0 from today_care_reminders), 'account deletion cascades through all care entries');
rollback;
