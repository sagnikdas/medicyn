-- Per-user ledger for parse-medicine billed calls.
--
-- A signed-in Google account is cheap; an Anthropic call is not. After #20
-- the function refuses anyone who is not a real user, but it still ran
-- unlimited extractions for anyone who was. This table is the cap: 40 calls
-- per rolling 24-hour window, keyed on the verified caller id, written only
-- by the edge function with the service role.
--
-- No client policies. The app never reads this, and a select-own policy
-- would only leak how close someone is to the cap. RLS is still enabled so
-- a forgotten grant cannot become an open table. The service role bypasses
-- RLS, which is the only intended writer.

create table parse_medicine_usage (
  user_id uuid primary key references auth.users (id) on delete cascade,
  window_start timestamptz not null default now(),
  call_count int not null default 0,
  constraint parse_medicine_usage_count_nonnegative check (call_count >= 0)
);

alter table parse_medicine_usage enable row level security;
