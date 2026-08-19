-- Push: where to send a notification, and what we have already sent.
--
-- Two tables, and the reason they are separate is worth stating. `device_tokens`
-- is routing information — volatile, rewritten whenever Android reissues a
-- token, and of no interest to anybody but the server. `care_alerts` is a
-- record of something we told a family, which is exactly the kind of fact this
-- schema keeps rather than discards (compare the revoked `care_links` rows).

-- ---------------------------------------------------------------------------
-- device_tokens
-- ---------------------------------------------------------------------------
-- One row per app install, keyed by the FCM registration token itself.
--
-- The token is the primary key rather than a surrogate id, and that choice is
-- the security-relevant one: an FCM token belongs to an *install*, not to an
-- account. Sign out of one Google account on a phone and into another, and the
-- token is unchanged. With the token as the key, the second sign-in's upsert
-- moves the row's `user_id`, so the phone stops receiving anything addressed to
-- the person who signed out. A surrogate key would instead leave two rows
-- claiming the same device and quietly deliver one family's missed-dose alerts
-- to whoever is holding the phone now.

create table device_tokens (
  token text primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  platform text not null check (platform in ('android', 'ios')),
  created_at timestamptz not null default now(),
  -- Touched on every registration, so a token that has stopped checking in is
  -- distinguishable from one that was never used.
  refreshed_at timestamptz not null default now()
);

create index device_tokens_user_id_idx on device_tokens (user_id);

alter table device_tokens enable row level security;

-- Read and delete your own rows; nothing else. Deliberately *not* readable by
-- a linked caregiver: a token is a capability to ring someone's phone, and
-- nothing in the app needs to hold one but the server. The edge function reads
-- these with the service role, which bypasses RLS.
--
-- Delete has a policy because sign-out uses it — a phone that has been handed
-- back should stop receiving the previous account's alerts immediately, not at
-- whatever point FCM next reissues its token.
create policy "device_tokens_read_own" on device_tokens
  for select using (user_id = (select auth.uid()));

create policy "device_tokens_delete_own" on device_tokens
  for delete using (user_id = (select auth.uid()));

-- No insert or update policy: registration goes through the function below.
-- This is not tidiness, it is the only way the "token belongs to an install"
-- rule above can hold. An ordinary `insert ... on conflict do update` cannot
-- move a row between accounts under RLS, because the update arm is checked
-- against the *existing* row — which belongs to whoever signed out. The
-- registration would simply fail, leaving the phone still addressed to them.
-- Deliberately no `app_version` column or argument. Phase 2's setup-health
-- panel will want the app version, the permission states and the alarm count
-- together, and adding one of them now — unpopulated, because nothing reads it
-- yet — is how the dead `deleted` column on `medicines` happened.
create or replace function public.register_device_token(
  p_token text,
  p_platform text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := (select auth.uid());
begin
  if me is null then
    raise exception 'not_authenticated';
  end if;
  if p_token is null or length(p_token) = 0 then
    raise exception 'invalid_token';
  end if;
  if p_platform not in ('android', 'ios') then
    raise exception 'invalid_platform';
  end if;

  insert into device_tokens (token, user_id, platform)
  values (p_token, me, p_platform)
  on conflict (token) do update
    set user_id = me,
        platform = p_platform,
        refreshed_at = now();
end;
$$;

revoke execute on function public.register_device_token(text, text) from public;
grant execute on function public.register_device_token(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- care_alerts
-- ---------------------------------------------------------------------------
-- What we have told the other side of a link, and when.
--
-- It earns its place three times over: it stops the same missed dose being
-- announced twice (two devices on one account each push the same
-- deterministically-id'd dose log, and each would otherwise announce it); it
-- gives the parent an answer to "what is being said about me", which the
-- symmetry promise will eventually need; and it is the only place a delivery
-- failure is visible at all, since a push that lands nowhere is otherwise
-- indistinguishable from one that worked.

create table care_alerts (
  id uuid primary key default gen_random_uuid(),
  link_id uuid not null references care_links (id) on delete cascade,
  recipient_id uuid not null references auth.users (id) on delete cascade,
  -- Matches the event names the client and the notify-care function share.
  kind text not null check (kind in ('missed_dose', 'data_changed')),
  -- Set for 'missed_dose' only: which dose this was about. Nullable rather
  -- than a separate table, because every other alert kind is stateless.
  dose_log_id uuid references dose_logs (id) on delete cascade,
  -- How many device tokens accepted it. Zero is the interesting value: it
  -- means the recipient's phone cannot currently be reached.
  delivered_count int not null default 0,
  sent_at timestamptz not null default now()
);

-- The de-duplication, and the reason it is not a partial index: Postgres
-- treats nulls as distinct in a unique index, so the `data_changed` rows
-- (which carry no dose) never collide with each other, while two attempts to
-- announce the same missed dose on the same link do. Keeping it total is what
-- lets `on conflict (link_id, dose_log_id) do nothing` infer it — a partial
-- index cannot be inferred through PostgREST, and the read-then-insert this
-- would otherwise need is exactly the race the index exists to close.
create unique index care_alerts_one_per_dose
  on care_alerts (link_id, dose_log_id);

create index care_alerts_recipient_idx on care_alerts (recipient_id, sent_at desc);

alter table care_alerts enable row level security;

-- Readable by both sides of the link it belongs to — the caregiver because it
-- is their alert, the patient because it is about them. Written only by the
-- edge function under the service role, so there is no insert/update/delete
-- policy at all; direct writes are refused, exactly as with `care_links`.
create policy "care_alerts_read_own_link" on care_alerts
  for select using (
    exists (
      select 1 from care_links
      where care_links.id = care_alerts.link_id
        and (care_links.patient_id = (select auth.uid())
             or care_links.caregiver_id = (select auth.uid()))
    )
  );
