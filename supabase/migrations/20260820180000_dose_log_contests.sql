-- A user correction note attached to an immutable dose log.
--
-- Dose logs stay append-only: nothing here changes `action` or the timestamps.
-- Art. 16 still needs a path to contest a fabricated missed dose, so the note
-- lives on its own row keyed by the log. The caregiver's feed may *read* it
-- (they already see the log); they must not write one in the patient's name.

create table public.dose_log_contests (
  dose_log_id uuid primary key references public.dose_logs (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  note text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint dose_log_contests_note_not_empty check (char_length(btrim(note)) > 0)
);

create index dose_log_contests_user_id_idx on public.dose_log_contests (user_id);

alter table public.dose_log_contests enable row level security;

-- Force user_id from the parent log so a payload cannot attach a note to
-- someone else's row while claiming a different owner. Updates cannot
-- re-parent the note or swap the owner.
create or replace function public.dose_log_contests_stamp_user_id()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  owner uuid;
begin
  if tg_op = 'INSERT' then
    select user_id into owner from dose_logs where id = new.dose_log_id;
    if owner is null then
      raise exception 'dose_log_not_found';
    end if;
    new.user_id := owner;
    return new;
  end if;
  new.user_id := old.user_id;
  new.dose_log_id := old.dose_log_id;
  return new;
end;
$$;

comment on function public.dose_log_contests_stamp_user_id() is
  'Forces dose_log_contests.user_id from the parent log; refuses to re-parent on update.';

drop trigger if exists dose_log_contests_stamp_user_id on public.dose_log_contests;
create trigger dose_log_contests_stamp_user_id
  before insert or update on public.dose_log_contests
  for each row
  execute function public.dose_log_contests_stamp_user_id();

revoke execute on function public.dose_log_contests_stamp_user_id() from public;
grant execute on function public.dose_log_contests_stamp_user_id() to authenticated;

do $g$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.dose_log_contests_stamp_user_id() to service_role;
  end if;
end;
$g$;

-- Owner and active caregiver both read: the note is about a log they can
-- already see. Writes are the patient's device only — same split as dose_logs.
create policy dose_log_contests_select on public.dose_log_contests
  for select using (public.can_access_user_data(user_id));

create policy dose_log_contests_insert on public.dose_log_contests
  for insert with check (user_id = (select auth.uid()));

create policy dose_log_contests_update on public.dose_log_contests
  for update using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
