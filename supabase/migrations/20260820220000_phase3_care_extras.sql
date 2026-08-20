-- Phase 3: refill stock on medicines, a phone the other side can ring,
-- silent-device detection from last_seen_at, and two new care-alert kinds.
--
-- Refill is a column on medicines (not a second table) because the caregiver
-- already writes that row when they log a new bottle, and the patient's
-- Taken path is the only decrement. Silent-device cannot be device-side —
-- the whole point is that the patient's app is not running — so the due
-- set is a SQL function the operator or a cron-invoked edge function reads.
-- The function does not call FCM: pg_net lives in the extensions schema
-- every security-definer function here excludes.

-- ---------------------------------------------------------------------------
-- Refill
-- ---------------------------------------------------------------------------

alter table public.medicines
  add column tablets_remaining integer
    check (tablets_remaining is null or tablets_remaining >= 0),
  add column tablets_per_dose integer
    check (tablets_per_dose is null or tablets_per_dose >= 1);

comment on column public.medicines.tablets_remaining is
  'Nullable on purpose: null means the user is not tracking this bottle. Taken on the patient device decrements it.';
comment on column public.medicines.tablets_per_dose is
  'How many tablets leave the bottle per answered dose. Null is treated as 1 when remaining is set.';

-- ---------------------------------------------------------------------------
-- Care-alert kinds
-- ---------------------------------------------------------------------------

alter table public.care_alerts
  drop constraint if exists care_alerts_kind_check;

alter table public.care_alerts
  add constraint care_alerts_kind_check
  check (kind in ('missed_dose', 'data_changed', 'device_silent', 'refill_low'));

-- One silent-device ping per link per UTC day. Postgres unique indexes treat
-- nulls as distinct, so the missed-dose (link_id, dose_log_id) index cannot
-- de-duplicate these — they have no dose_log_id.
create unique index care_alerts_device_silent_day
  on public.care_alerts (link_id, ((sent_at at time zone 'utc')::date))
  where kind = 'device_silent';

-- One refill warning per link per UTC day, even if several medicines are low.
create unique index care_alerts_refill_low_day
  on public.care_alerts (link_id, ((sent_at at time zone 'utc')::date))
  where kind = 'refill_low';

-- ---------------------------------------------------------------------------
-- Phone number the other person rings
-- ---------------------------------------------------------------------------
-- Each side stores *their own* number so the other can call it. Direct
-- updates on care_links have no write policy on purpose; this is the only
-- authenticated path.

create function public.set_own_care_phone(phone text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := (select auth.uid());
  cleaned text;
  n int;
begin
  if me is null then
    raise exception 'not_authenticated';
  end if;

  cleaned := nullif(btrim(phone), '');
  if cleaned is not null and char_length(cleaned) > 32 then
    raise exception 'phone_too_long';
  end if;

  update care_links
     set patient_phone = case when patient_id = me then cleaned else patient_phone end,
         caregiver_phone = case when caregiver_id = me then cleaned else caregiver_phone end
   where status = 'active'
     and (patient_id = me or caregiver_id = me);

  get diagnostics n = row_count;
  if n = 0 then
    raise exception 'no_active_link';
  end if;
end;
$$;

comment on function public.set_own_care_phone(text) is
  'Stores the caller''s own phone on the active care link so the other person can ring it. Empty string clears it.';

revoke all on function public.set_own_care_phone(text) from public;
grant execute on function public.set_own_care_phone(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Silent devices
-- ---------------------------------------------------------------------------
-- A patient whose last_seen_at (or, if they have never checked in, the
-- moment the link was confirmed) is older than 24 hours. Distinct from a
-- missed dose: this fires when the app did not run, so no sweep could have
-- produced one.

create function public.silent_devices_due(at timestamptz default now())
returns table (
  link_id uuid,
  patient_id uuid,
  caregiver_id uuid,
  last_seen_at timestamptz
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select l.id,
         l.patient_id,
         l.caregiver_id,
         p.last_seen_at
    from care_links l
    join profiles p on p.user_id = l.patient_id
   where l.status = 'active'
     and l.caregiver_id is not null
     and coalesce(p.last_seen_at, l.accepted_at, l.created_at)
         < at - interval '24 hours'
     and not exists (
       select 1
         from care_alerts a
        where a.link_id = l.id
          and a.kind = 'device_silent'
          and (a.sent_at at time zone 'utc')::date
              = (at at time zone 'utc')::date
     );
$$;

comment on function public.silent_devices_due(timestamptz) is
  'Active care pairs whose patient phone has not checked in for 24 hours and have not already been pinged today. Operator / service_role; the edge function sends FCM.';

revoke all on function public.silent_devices_due(timestamptz) from public;
revoke all on function public.silent_devices_due(timestamptz) from authenticated;

do $g$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke all on function public.silent_devices_due(timestamptz) from anon;
    revoke all on function public.set_own_care_phone(text) from anon;
  end if;
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.silent_devices_due(timestamptz) to service_role;
    grant execute on function public.set_own_care_phone(text) to service_role;
  end if;
end;
$g$;
