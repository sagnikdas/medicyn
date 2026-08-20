-- Phase 2: caregiver editing is now a real write, not just a permitted one.
--
-- Three things the database has to hold that the app could not fake from
-- client state alone:
--
--   1. A caregiver may add or edit a patient's medicines, but may not delete
--      them. Deletion has no undo, and it is the write most likely to be done
--      by the wrong person in a hurry. The old `for all` policy allowed it.
--   2. An append-only change history, stamped with whoever's JWT actually
--      wrote the row — not the `updated_by` the client sent, which a
--      caregiver could set to the patient's id and make an edit look like
--      the parent's.
--   3. Whether the patient's phone can actually ring: notification /
--      exact-alarm / battery-exemption flags plus how many alarms are armed.
--      `last_seen_at` already exists; these are the rest of setup health.
--
-- Owner reassignment is also refused. `can_access_user_data` is true for
-- both the patient's rows and the caregiver's own, so an UPDATE that moved
-- `user_id` from patient to caregiver would pass both USING and WITH CHECK
-- and steal the row.

-- ---------------------------------------------------------------------------
-- medicines / schedules: split the all-policy; delete is owner-only
-- ---------------------------------------------------------------------------

drop policy if exists "medicines_access" on public.medicines;
drop policy if exists "schedules_access" on public.schedules;

create policy "medicines_read" on public.medicines
  for select using (public.can_access_user_data(user_id));

create policy "medicines_insert" on public.medicines
  for insert with check (public.can_access_user_data(user_id));

create policy "medicines_update" on public.medicines
  for update
  using (public.can_access_user_data(user_id))
  with check (public.can_access_user_data(user_id));

create policy "medicines_delete" on public.medicines
  for delete using (user_id = (select auth.uid()));

create policy "schedules_read" on public.schedules
  for select using (public.can_access_user_data(user_id));

create policy "schedules_insert" on public.schedules
  for insert with check (public.can_access_user_data(user_id));

create policy "schedules_update" on public.schedules
  for update
  using (public.can_access_user_data(user_id))
  with check (public.can_access_user_data(user_id));

create policy "schedules_delete" on public.schedules
  for delete using (user_id = (select auth.uid()));

-- Stamp the writer from the JWT, and refuse a change of owner. INVOKER so
-- `auth.uid()` is the client, not the table owner.
create or replace function public.stamp_row_writer()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  if TG_OP = 'UPDATE' and NEW.user_id is distinct from OLD.user_id then
    raise exception 'cannot_reassign_owner';
  end if;
  if TG_OP = 'UPDATE'
     and TG_TABLE_NAME = 'schedules'
     and NEW.medicine_id is distinct from OLD.medicine_id then
    raise exception 'cannot_reassign_owner';
  end if;
  if (select auth.uid()) is not null then
    NEW.updated_by := (select auth.uid());
  end if;
  return NEW;
end;
$$;

create trigger medicines_stamp_writer
  before insert or update on public.medicines
  for each row execute function public.stamp_row_writer();

create trigger schedules_stamp_writer
  before insert or update on public.schedules
  for each row execute function public.stamp_row_writer();

-- ---------------------------------------------------------------------------
-- append-only edit history
-- ---------------------------------------------------------------------------

create table public.medicine_edits (
  id uuid primary key default gen_random_uuid(),
  medicine_id uuid not null references public.medicines (id) on delete cascade,
  owner_id uuid not null references auth.users (id) on delete cascade,
  -- Null if the actor's account is later deleted; the summary still stands.
  actor_id uuid references auth.users (id) on delete set null,
  summary text not null,
  created_at timestamptz not null default now()
);

create index medicine_edits_medicine_created_idx
  on public.medicine_edits (medicine_id, created_at desc);

create index medicine_edits_owner_created_idx
  on public.medicine_edits (owner_id, created_at desc);

alter table public.medicine_edits enable row level security;

create policy "medicine_edits_read" on public.medicine_edits
  for select using (public.can_access_user_data(owner_id));

-- Clients read; only the trigger writes. Defence in depth on top of there
-- being no insert/update/delete policy.
revoke insert, update, delete on public.medicine_edits from authenticated;
grant select on public.medicine_edits to authenticated;

-- DEFINER: authenticated has no insert grant, and the function must still
-- be able to write the history row after a legitimate medicine upsert.
create or replace function public.record_medicine_edit()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  verb text;
  strength text;
begin
  verb := case when TG_OP = 'INSERT' then 'Added' else 'Changed' end;
  strength := nullif(btrim(coalesce(NEW.strength, '')), '');
  insert into public.medicine_edits (medicine_id, owner_id, actor_id, summary)
  values (
    NEW.id,
    NEW.user_id,
    coalesce(NEW.updated_by, NEW.user_id),
    btrim(verb || ' ' || NEW.drug_name || coalesce(' ' || strength, ''))
  );
  return NEW;
end;
$$;

revoke all on function public.stamp_row_writer() from public;
grant execute on function public.stamp_row_writer() to authenticated;

revoke all on function public.record_medicine_edit() from public;
grant execute on function public.record_medicine_edit() to authenticated;

create trigger medicines_record_edit
  after insert or update on public.medicines
  for each row execute function public.record_medicine_edit();

-- ---------------------------------------------------------------------------
-- setup health on the patient's profile
-- ---------------------------------------------------------------------------

alter table public.profiles
  add column if not exists notifications_allowed boolean,
  add column if not exists exact_alarms_allowed boolean,
  add column if not exists battery_exemption boolean,
  add column if not exists armed_alarm_count integer
    check (armed_alarm_count is null or armed_alarm_count >= 0),
  add column if not exists health_checked_at timestamptz;

comment on column public.profiles.notifications_allowed is
  'Whether this phone currently allows notifications. Written only by the owner; a linked caregiver reads it as setup health.';
comment on column public.profiles.exact_alarms_allowed is
  'Whether exact alarms are permitted on this phone.';
comment on column public.profiles.battery_exemption is
  'Whether Android battery optimisation is ignored for this app.';
comment on column public.profiles.armed_alarm_count is
  'Pending notification requests at last check-in — a proxy for alarms actually armed.';
comment on column public.profiles.health_checked_at is
  'When the owner last reported the permission / armed-count snapshot.';
