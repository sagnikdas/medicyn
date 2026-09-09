-- Per-user ledger for parse-prescription billed calls.
--
-- Same pattern as parse_medicine_usage (20260819164000), kept as its own
-- table rather than sharing one: this is a different, tighter cap (15 per
-- rolling 24h vs. 40) because a multi-page prescription/discharge document
-- is a materially more expensive Claude call than a single label+
-- transcript, and scanning a whole prescription is inherently rarer than a
-- routine per-medicine label scan.
--
-- No client policies. The app never reads this, and a select-own policy
-- would only leak how close someone is to the cap. RLS is still enabled so
-- a forgotten grant cannot become an open table. The service role bypasses
-- RLS, which is the only intended writer.

create table parse_prescription_usage (
  user_id uuid primary key references auth.users (id) on delete cascade,
  window_start timestamptz not null default now(),
  call_count int not null default 0,
  constraint parse_prescription_usage_count_nonnegative check (call_count >= 0)
);

alter table parse_prescription_usage enable row level security;
