-- Drops a constraint the previous migration should never have added.
--
-- `20260819140000_schedule_field_constraints.sql` added
-- `dose_logs_action_known` on the belief that `dose_logs.action` was
-- unconstrained. It was not: `init.sql` has carried
-- `check (action in ('taken', 'snoozed', 'missed'))` since the first
-- migration, which Postgres named `dose_logs_action_check`. The survey that
-- preceded that migration only looked at constraints on `schedules`, so it
-- reported nothing for `dose_logs` and the wrong conclusion followed.
--
-- The result was two identical CHECKs on one column: every write evaluated
-- both, and a reader of the schema had to work out whether the duplication
-- meant something. It did not.
--
-- The original constraint stays. Only the duplicate goes.
--
-- Kept as its own migration rather than by editing the one that added it,
-- because that one has already been applied to the hosted project. A
-- migration file that no longer says what actually ran is worse than an
-- extra file.

alter table public.dose_logs
  drop constraint if exists dose_logs_action_known;
