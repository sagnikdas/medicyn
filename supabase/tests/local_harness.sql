-- Enough of Supabase's own plumbing to run the RLS test on a plain Postgres,
-- for when Docker (and so `supabase start`) isn't available.
--
--   createdb dosely_rls_test
--   psql -d dosely_rls_test -v ON_ERROR_STOP=1 \
--     -f supabase/tests/local_harness.sql \
--     -f supabase/migrations/20260812121223_init.sql \
--     -f supabase/migrations/20260812122500_schedule_interval_hours.sql \
--     -f supabase/migrations/20260818143000_row_versioning.sql \
--     -f supabase/migrations/20260818161500_care_links.sql \
--     -f supabase/migrations/20260819110000_push_notifications.sql \
--     -f supabase/migrations/20260819120000_fix_naive_client_timestamps.sql \
--     -f supabase/migrations/20260819140000_schedule_field_constraints.sql \
--     -f supabase/migrations/20260819150000_drop_redundant_dose_logs_check.sql \
--     -f supabase/migrations/20260819160000_care_alerts_active_caregiver.sql \
--     -f supabase/migrations/20260819161000_claimed_link_expiry.sql \
--     -f supabase/migrations/20260819162000_device_token_possession.sql \
--     -f supabase/migrations/20260819163000_dose_logs_recorded_by.sql \
--     -f supabase/migrations/20260819164000_parse_medicine_quota.sql \
--     -f supabase/migrations/20260819165000_claimed_link_identity.sql \
--     -f supabase/migrations/20260820170000_consents.sql \
--     -f supabase/migrations/20260820180000_dose_log_contests.sql \
--     -f supabase/tests/care_links_rls_test.sql
--
-- and the push tables' own assertions, which need a fresh database because
-- both tests set up the same three users:
--
--   dropdb --if-exists dosely_rls_test && createdb dosely_rls_test
--   psql -d dosely_rls_test -v ON_ERROR_STOP=1 \
--     -f supabase/tests/local_harness.sql \
--     -f supabase/migrations/*.sql (in the order above) \
--     -f supabase/tests/push_rls_test.sql
--
-- and the schedule constraint assertions, which also want a fresh database:
--
--   dropdb --if-exists dosely_rls_test && createdb dosely_rls_test
--   psql -d dosely_rls_test -v ON_ERROR_STOP=1 \
--     -f supabase/tests/local_harness.sql \
--     -f supabase/migrations/*.sql (in the order above) \
--     -f supabase/tests/schedule_constraints_test.sql
--
-- and the dose-log contest assertions:
--
--   dropdb --if-exists dosely_rls_test && createdb dosely_rls_test
--   psql -d dosely_rls_test -v ON_ERROR_STOP=1 \
--     -f supabase/tests/local_harness.sql \
--     -f supabase/migrations/*.sql (in the order above) \
--     -f supabase/tests/dose_log_contests_test.sql
--
-- Note the assertions print to stderr, not stdout, so redirect both when
-- counting them.
--
-- Later migrations after push_notifications were missing from the list
-- above until they were added; a run without them exercises a schema that
-- no longer exists anywhere.
--
-- This stubs the parts of the platform the policies depend on. It is a
-- convenience for testing policy *logic*; it is not a claim that the local
-- database behaves like the hosted one in every respect.

-- Deliberately no `create extension pgcrypto` in `public`. Supabase installs
-- extensions into an `extensions` schema, so a function that pins its
-- search_path cannot reach them. Creating pgcrypto here would hide that
-- difference and let a migration pass locally then fail on the hosted
-- project — which is exactly what happened once.
create schema if not exists auth;

-- Only the columns the app's foreign keys actually reference.
create table if not exists auth.users (
  id uuid primary key,
  email text
);

-- The real one reads the verified JWT the API gateway attached. Same source
-- of truth here: whatever the session has been told it is.
create or replace function auth.uid() returns uuid
language sql stable as $$
  select nullif(current_setting('request.jwt.claims', true)::json ->> 'sub', '')::uuid;
$$;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
end;
$$;

grant usage on schema public, auth to authenticated;

-- Row-level security only *filters* rows a role is otherwise allowed to
-- touch. Without these grants the test would fail with permission errors and
-- prove nothing about the policies.
alter default privileges in schema public
  grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema public
  grant execute on functions to authenticated;
