-- Medicyn core schema: medicines, schedules, dose_logs.
-- Local Drift DB on-device is the source of truth for scheduling/firing
-- reminders; these tables are sync/backup only, scoped per user via RLS.

create table medicines (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  drug_name text not null,
  strength text,
  form text,
  dose_amount text,
  notes text,
  created_at timestamptz not null default now()
);

create table schedules (
  id uuid primary key default gen_random_uuid(),
  medicine_id uuid not null references medicines (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  frequency_type text not null,
  times jsonb not null default '[]'::jsonb,
  days_of_week int[] not null default '{}',
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table dose_logs (
  id uuid primary key default gen_random_uuid(),
  schedule_id uuid not null references schedules (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  scheduled_at timestamptz not null,
  action text not null check (action in ('taken', 'snoozed', 'missed')),
  logged_at timestamptz not null default now(),
  source text not null default 'notification'
);

create index medicines_user_id_idx on medicines (user_id);
create index schedules_user_id_idx on schedules (user_id);
create index schedules_medicine_id_idx on schedules (medicine_id);
create index dose_logs_user_id_idx on dose_logs (user_id);
create index dose_logs_schedule_id_idx on dose_logs (schedule_id);

alter table medicines enable row level security;
alter table schedules enable row level security;
alter table dose_logs enable row level security;

create policy "medicines_owner_all" on medicines
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "schedules_owner_all" on schedules
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "dose_logs_owner_all" on dose_logs
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
