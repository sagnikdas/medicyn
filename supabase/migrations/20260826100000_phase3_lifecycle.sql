-- Phase 3: make a reminder's lifecycle explicit instead of overloading the
-- legacy `active` boolean. Existing rows remain active/completed according to
-- their current value; the nullable dates allow older clients to keep syncing
-- while they upgrade.

alter table public.schedules
  add column if not exists status text,
  add column if not exists start_date timestamptz,
  add column if not exists end_date timestamptz,
  add column if not exists pause_until timestamptz;

update public.schedules
set status = case
  when frequency_type = 'asNeeded' then 'asNeeded'
  when active then 'active'
  else 'completed'
end
where status is null;

alter table public.schedules
  alter column status set default 'active';

alter table public.schedules
  add constraint schedules_status_known
  check (status is null or status in ('active', 'paused', 'completed', 'asNeeded'));

alter table public.schedules
  add constraint schedules_lifecycle_dates_ordered
  check (end_date is null or start_date is null or end_date > start_date);

create index if not exists schedules_lifecycle_idx
  on public.schedules (user_id, status, start_date, end_date);
