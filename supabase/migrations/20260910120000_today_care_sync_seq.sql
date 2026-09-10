-- A cursor for incremental pulls, kept deliberately separate from
-- `updated_at`. `updated_at` is client-supplied on purpose (see
-- 20260818143000_row_versioning.sql) so last-write-wins reflects when an
-- offline edit was actually made, not when it happened to reach the server.
-- That is exactly why it is unsafe as a "changed since I last looked"
-- filter: a device with a badly wrong clock could write an edit stamped
-- earlier than another device's last pull cursor, and that edit would then
-- be silently invisible to every other device, forever. `sync_seq` is
-- assigned by a trigger from a sequence, never by the client, so it cannot
-- skew — every accepted write gets a value strictly greater than every write
-- that landed before it, regardless of any client's clock.
create sequence public.today_care_reminders_sync_seq;

alter table public.today_care_reminders
  add column sync_seq bigint;

-- Existing rows predate this column. Backfill in `updated_at` order so
-- older edits keep a lower cursor value than newer ones, rather than
-- stamping every existing row with the same "just migrated" instant.
with ordered as (
  select id, row_number() over (order by updated_at, id) as rn
  from public.today_care_reminders
)
update public.today_care_reminders t
set sync_seq = ordered.rn
from ordered
where ordered.id = t.id;

select setval(
  'public.today_care_reminders_sync_seq',
  coalesce((select max(sync_seq) from public.today_care_reminders), 0) + 1,
  false
);

alter table public.today_care_reminders
  alter column sync_seq set not null;

create unique index today_care_reminders_sync_seq_idx
  on public.today_care_reminders (sync_seq);

create index today_care_reminders_user_syncseq_idx
  on public.today_care_reminders (user_id, sync_seq);

create function public.stamp_today_care_sync_seq() returns trigger
language plpgsql set search_path = public as $$
begin
  new.sync_seq := nextval('today_care_reminders_sync_seq');
  return new;
end;
$$;

-- Trigger names fire in alphabetical order for the same event. This name
-- ("stamp_...") sorts before the existing "today_care_version_guard", so it
-- always runs first: it stamps a fresh sync_seq onto NEW, and only then does
-- the guard decide whether to keep NEW or discard the whole row by
-- returning OLD. A rejected stale update therefore reverts sync_seq right
-- along with everything else — a losing write can never advance the cursor.
create trigger today_care_stamp_sync_seq before insert or update
  on public.today_care_reminders
  for each row execute function public.stamp_today_care_sync_seq();
