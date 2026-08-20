-- stamp_row_writer is attached to both medicines and schedules. The first
-- version mentioned NEW.medicine_id in the same IF expression as the
-- table-name guard. PL/pgSQL evaluates that expression as a whole, so a
-- write to medicines — which has no medicine_id — failed with
-- `record "new" has no field "medicine_id"` and the client mapped it to a
-- connection error. Every caregiver (and parent) save of a medicine was
-- broken from the moment the previous migration landed.

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
  if (select auth.uid()) is not null then
    NEW.updated_by := (select auth.uid());
  end if;
  return NEW;
end;
$$;

create or replace function public.stamp_schedule_medicine()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  if TG_OP = 'UPDATE' and NEW.medicine_id is distinct from OLD.medicine_id then
    raise exception 'cannot_reassign_owner';
  end if;
  return NEW;
end;
$$;

drop trigger if exists schedules_guard_medicine on public.schedules;
create trigger schedules_guard_medicine
  before insert or update on public.schedules
  for each row execute function public.stamp_schedule_medicine();

revoke all on function public.stamp_schedule_medicine() from public;
grant execute on function public.stamp_schedule_medicine() to authenticated;

do $g$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.stamp_row_writer() to service_role;
    grant execute on function public.stamp_schedule_medicine() to service_role;
    grant execute on function public.record_medicine_edit() to service_role;
  end if;
end;
$g$;
