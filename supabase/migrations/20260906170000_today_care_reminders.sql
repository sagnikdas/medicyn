-- Personal care entries are backed up just like medicine reminders. Keep
-- deletion versions so offline devices cannot resurrect removed entries.
create table public.today_care_reminders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (length(btrim(title)) > 0),
  kind text not null check (kind in ('test', 'scan', 'therapy', 'appointment', 'other')),
  scheduled_at timestamptz not null,
  location text not null default '',
  notes text not null default '',
  reminder_minutes integer check (reminder_minutes is null or reminder_minutes >= 0),
  completed boolean not null default false,
  updated_at timestamptz not null default now(),
  deleted boolean not null default false
);

create index today_care_reminders_owner_idx
  on public.today_care_reminders(user_id, id);

alter table public.today_care_reminders enable row level security;

create policy today_care_owner on public.today_care_reminders
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

grant select, insert, update, delete on public.today_care_reminders to authenticated;

-- A client timestamp represents when the offline edit was made, matching
-- the existing medicine sync protocol. The server enforces the comparison
-- atomically, including a race between a pull and a subsequent upsert.
create function public.guard_today_care_version() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.user_id is distinct from old.user_id or new.id is distinct from old.id then
    raise exception 'Care reminder ownership cannot change' using errcode = '42501';
  end if;
  if new.updated_at <= old.updated_at then
    return old;
  end if;
  return new;
end;
$$;

create trigger today_care_version_guard before update on public.today_care_reminders
  for each row execute function public.guard_today_care_version();
