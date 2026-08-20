-- Retention: dose history, alerts, revoked links and stale device tokens
-- grew without a TTL. GDPR storage limitation (Art. 5(1)(e)) wants a
-- period and a job that enforces it. Medicines, schedules, profiles and
-- consents are out of scope here — they live until the account or the
-- medicine is deleted.
--
-- Periods:
--   dose_logs      24 months from logged_at
--   care_alerts    12 months from sent_at
--   revoked care_links  12 months from disconnect
--   device_tokens  90 days without a refresh
--
-- Active, pending and claimed care_links are never pruned. A revoked row
-- with a null revoked_at (legacy) still ages out via
-- coalesce(revoked_at, accepted_at, created_at).
--
-- Callable by the operator (postgres / service_role). Not granted to
-- authenticated: a client must not be able to wipe another family's
-- history by invoking this. If the cron job is not listed after migrate,
-- enable pg_cron in the Supabase dashboard; the function is still
-- callable by the operator either way.

create function public.prune_expired_data()
returns table(entity text, deleted_count bigint)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  n bigint;
begin
  -- Dose logs first: care_alerts.dose_log_id is on delete cascade, so
  -- alerts that named an expired log go with it and are not counted twice.
  delete from dose_logs
   where logged_at < now() - interval '24 months';
  get diagnostics n = row_count;
  entity := 'dose_logs';
  deleted_count := n;
  return next;

  delete from care_alerts
   where sent_at < now() - interval '12 months';
  get diagnostics n = row_count;
  entity := 'care_alerts';
  deleted_count := n;
  return next;

  delete from care_links
   where status = 'revoked'
     and coalesce(revoked_at, accepted_at, created_at)
         < now() - interval '12 months';
  get diagnostics n = row_count;
  entity := 'care_links';
  deleted_count := n;
  return next;

  delete from device_tokens
   where refreshed_at < now() - interval '90 days';
  get diagnostics n = row_count;
  entity := 'device_tokens';
  deleted_count := n;
  return next;
end;
$$;

comment on function public.prune_expired_data() is
  'Deletes dose_logs older than 24 months, care_alerts older than 12 months, revoked care_links older than 12 months, and device_tokens idle for 90 days. Operator-only; scheduled by pg_cron when that extension is enabled.';

revoke all on function public.prune_expired_data() from public;
revoke all on function public.prune_expired_data() from authenticated;

do $g$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke all on function public.prune_expired_data() from anon;
  end if;
  -- Hosted cron and the dashboard SQL editor run as postgres / service_role.
  -- Local harness never creates service_role.
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.prune_expired_data() to service_role;
  end if;
end;
$g$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'prune-expired-data',
      '20 3 * * *',
      $cron$select public.prune_expired_data()$cron$
    );
  end if;
end
$$;
