-- Per-row versioning, so sync can carry an *edit* rather than only an insert.
--
-- Until now `pullAll` was insert-only: a row that already existed on a device
-- was never touched again, because there was nothing to compare the two
-- copies by. These two columns are that comparison.
--
-- `updated_at` is supplied by the client, not by a trigger or `now()`. That
-- is deliberate and it is the whole point: this app is offline-first, so the
-- moment an edit *reaches* the server says nothing useful about when it was
-- made. A phone that has been offline since yesterday would otherwise beat an
-- edit made five minutes ago on another device. The cost is that a device
-- with a badly wrong clock can win an argument it should have lost — an
-- acceptable trade, and the reason every reminder shows who last changed it.
--
-- `dose_logs` is deliberately left alone. A dose log is an append-only record
-- of something that happened at a moment in time; nothing ever edits one, so
-- there is no conflict to resolve.

alter table medicines
  add column updated_at timestamptz not null default now(),
  add column updated_by uuid references auth.users (id) on delete set null;

alter table schedules
  add column updated_at timestamptz not null default now(),
  add column updated_by uuid references auth.users (id) on delete set null;

-- Existing rows have never been edited, so their last change was their
-- creation. Saying so is more honest than stamping them all with the moment
-- this migration happened to run, and it keeps them from spuriously beating
-- a genuine older edit sitting unsynced on someone's phone.
update medicines set updated_at = created_at, updated_by = user_id;
update schedules set updated_at = created_at, updated_by = user_id;

-- Pull fetches by user and orders by this; the index keeps that cheap once a
-- pull becomes incremental ("everything changed since I last looked").
create index medicines_user_updated_idx on medicines (user_id, updated_at);
create index schedules_user_updated_idx on schedules (user_id, updated_at);
