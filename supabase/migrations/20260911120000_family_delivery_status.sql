-- Family-delivery status (#98): did an edit actually reach the other side's
-- phone, not just the server.
--
-- The building block this needs is a per-user "last confirmed sync" moment,
-- readable by a linked caregiver the same way setup health already is. Two
-- candidates already existed and both were rejected:
--
--   * `SyncStatusStore` (app/lib/data/remote/sync_status.dart) tracks exactly
--     this, but only in `SharedPreferences` on the device itself. It was
--     never written to Supabase, so the caregiver's phone has no way to read
--     it — it answers "is *my* backup healthy", not "has my edit reached
--     them".
--   * `profiles.last_seen_at` is already cross-device readable, but it is
--     stamped by `reportOwnDeviceHealth` independently of whether the pull
--     that actually applies a caregiver's edit succeeded — a phone with a
--     flaky connection can fail every pull yet still complete the separate
--     health-report write that touches `last_seen_at`. Reusing it here would
--     make the indicator claim delivery that never happened.
--
-- So this adds one column, `last_synced_at`, stamped only when this device's
-- own pull of medicines/schedules/dose-log-contests genuinely completed
-- without error (see `SyncService.pullAll`/`pullEditableTables` returning a
-- success bool, and `CareService.recordSyncSuccess`). No new table, no
-- acknowledgement/read-receipt protocol: a caregiver's change-history view
-- compares an edit's `created_at` against the patient's `last_synced_at` and
-- shows "delivered" or "pending" — a snapshot, not a guarantee.

alter table public.profiles
  add column if not exists last_synced_at timestamptz;

comment on column public.profiles.last_synced_at is
  'When this account''s device last completed a pull of its editable tables '
  '(medicines/schedules/contest notes) without a network error. Distinct '
  'from last_seen_at, which stamps on every health check-in regardless of '
  'whether that pull actually succeeded. A linked caregiver compares a '
  'medicine_edits.created_at against this to show whether the edit has '
  'reached the patient''s phone yet.';

-- Readable by the same rule as the rest of the profile (profiles_read from
-- care_links.sql already covers it — this is a plain column add, no policy
-- change needed) and writable only by the owner (profiles_write_own), same
-- as health_checked_at and last_seen_at above it.
