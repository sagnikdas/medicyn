-- silent_devices_due excluded a link for the rest of the UTC day the moment
-- one care_alerts row existed for it, regardless of whether that row ever
-- actually reached the caregiver. A send that failed — no registered token,
-- an FCM error — left that day's row at delivered_count = 0 and the
-- function simply stopped returning the link: notify-care's own retry logic
-- (see RETRY_IN_FLIGHT in index.ts) never got the chance to run, because
-- this query never handed the row back to it. Only a row that actually
-- delivered should count as "already told them today".
create or replace function public.silent_devices_due(at timestamptz default now())
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
          and a.delivered_count > 0
     );
$$;

comment on function public.silent_devices_due(timestamptz) is
  'Active care pairs whose patient phone has not checked in for 24 hours and have not yet been successfully pinged today. Operator / service_role; the edge function sends FCM.';
