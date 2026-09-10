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

-- A non-constant default (nextval()) forces Postgres to rewrite the table
-- rather than add the column as metadata only, backfilling every existing
-- row with its own sequence value in one pass. This is deliberately a
-- single statement, not add-then-backfill-then-not-null: this table takes
-- live writes, and a separate backfill step would leave a window where a
-- concurrent insert lands with no value at all, exactly the failure a
-- three-step version of this migration hit against the real database.
-- ADD COLUMN takes an exclusive lock for the (brief, single-pass) rewrite,
-- so nothing can write a row past this statement without a value. The
-- relative order backfilled rows land in doesn't matter — sync_seq is a
-- pull cursor, not a conflict-resolution timestamp, and every existing row
-- ends up greater than a fresh device's starting cursor of 0 regardless.
alter table public.today_care_reminders
  add column sync_seq bigint not null default nextval('today_care_reminders_sync_seq');

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
