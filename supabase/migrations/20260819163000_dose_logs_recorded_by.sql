-- Dose history is a record of what happened on the patient's device, not a
-- shared notepad. Until now `dose_logs_access` was `for all` under
-- `can_access_user_data`, so an active caregiver could insert a 'taken' row
-- for the patient and both feeds would render it identically to a genuine
-- Taken tap. Medicines and schedules still need caregiver writes — those
-- policies are untouched. Dose logs do not.
--
-- Two halves, both load-bearing:
--
--   * Row-level security: anyone on the link may *read* a dose log (the
--     feed), but only the patient may write one. `user_id = auth.uid()` is
--     the whole rule; a caregiver's modified client that upserts with the
--     patient's user_id fails the WITH CHECK.
--   * `recorded_by`: stamped by a BEFORE INSERT trigger from `auth.uid()`,
--     never from the payload. The official client does not send this column
--     (see `_syncDoseLogs`); the trigger is what keeps that working while
--     still refusing a spoofed author. Updates cannot change it, so an
--     upsert that collides with an existing row cannot launder the stamp.

alter table public.dose_logs
  add column recorded_by uuid references auth.users (id) on delete set null;

-- Existing rows predate the column. We cannot know a forger after the fact,
-- so they are attributed to the patient they already belong to.
update public.dose_logs set recorded_by = user_id where recorded_by is null;

-- Even a client that omits the column gets the caller, not a guess. The
-- trigger below overwrites a supplied value too; this default is the
-- fallback for a write that somehow bypassed it.
alter table public.dose_logs
  alter column recorded_by set default auth.uid();

create or replace function public.dose_logs_stamp_recorded_by()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    new.recorded_by := (select auth.uid());
    return new;
  end if;
  new.recorded_by := old.recorded_by;
  return new;
end;
$$;

comment on function public.dose_logs_stamp_recorded_by() is
  'Forces dose_logs.recorded_by to the caller on insert; refuses to change it on update.';

drop trigger if exists dose_logs_stamp_recorded_by on public.dose_logs;
create trigger dose_logs_stamp_recorded_by
  before insert or update on public.dose_logs
  for each row
  execute function public.dose_logs_stamp_recorded_by();

revoke execute on function public.dose_logs_stamp_recorded_by() from public;
grant execute on function public.dose_logs_stamp_recorded_by() to authenticated;

-- The service role bypasses RLS but still fires triggers, and Postgres 15
-- requires EXECUTE on the trigger function from the role that writes the
-- row. Absent locally, where local_harness never creates it.
do $g$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.dose_logs_stamp_recorded_by() to service_role;
  end if;
end;
$g$;

drop policy "dose_logs_access" on public.dose_logs;

-- Patient and active caregiver both read: that is the feed, and the
-- symmetry promise. Writes are the patient's device only.
create policy "dose_logs_select" on public.dose_logs
  for select using (public.can_access_user_data(user_id));

create policy "dose_logs_insert" on public.dose_logs
  for insert with check (user_id = (select auth.uid()));

create policy "dose_logs_update" on public.dose_logs
  for update using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy "dose_logs_delete" on public.dose_logs
  for delete using (user_id = (select auth.uid()));
