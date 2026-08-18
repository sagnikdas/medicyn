-- The care link: exactly one caregiver paired with exactly one parent, and
-- the row-level security that lets the caregiver act on the parent's data.
--
-- This is the one migration in the project where a mistake reaches across
-- accounts, so the shape is deliberately conservative:
--
--   * Access is *directional*. A caregiver can read and write their parent's
--     medicines, schedules and dose logs. The parent gets no access to the
--     caregiver's own rows — the caregiver may be someone else's patient, or
--     simply have their own prescriptions, and none of that is the parent's
--     business. Symmetry in the product means the parent sees everything
--     recorded *about them*, which this already gives them as the owner.
--
--   * Nobody selects `care_links` to find an invite. Codes are claimed
--     through a security-definer function, so a guessed code reveals nothing
--     and an ungessed one reveals nothing either.
--
--   * A claimed code still is not a link. The parent has to confirm the
--     named person. Possession of the code alone never grants access.

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
-- Needed before links are useful: confirming "Priya wants to connect" needs a
-- name to show, and the feed needs one to attribute changes to. `last_seen_at`
-- is what silent-device detection will later watch.

create table profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  timezone text,
  last_seen_at timestamptz,
  created_at timestamptz not null default now()
);

alter table profiles enable row level security;

-- ---------------------------------------------------------------------------
-- care_links
-- ---------------------------------------------------------------------------
-- Lifecycle: pending (code issued) -> claimed (a caregiver entered it) ->
-- active (the parent confirmed them) -> revoked. Revoked rows are kept rather
-- than deleted, so "who could see my medicines, and when" stays answerable.

create type care_link_status as enum ('pending', 'claimed', 'active', 'revoked');

create table care_links (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references auth.users (id) on delete cascade,
  -- Null until someone claims the invite code.
  caregiver_id uuid references auth.users (id) on delete cascade,
  status care_link_status not null default 'pending',
  invite_code text,
  -- Invites are short-lived on purpose: a six-digit code is only as safe as
  -- the window it is guessable in.
  expires_at timestamptz,
  -- For the call button. Each side stores the number the *other* side rings.
  patient_phone text,
  caregiver_phone text,
  created_at timestamptz not null default now(),
  claimed_at timestamptz,
  accepted_at timestamptz,
  revoked_at timestamptz,
  constraint care_links_not_self check (caregiver_id is null or caregiver_id <> patient_id)
);

-- One-to-one, enforced by the database rather than by app code that can be
-- raced. A person may sit on at most one live link from either side; revoked
-- rows are excluded so a pair can be broken and remade.
create unique index care_links_one_live_per_patient
  on care_links (patient_id) where status <> 'revoked';
create unique index care_links_one_live_per_caregiver
  on care_links (caregiver_id) where status <> 'revoked' and caregiver_id is not null;

create unique index care_links_pending_code
  on care_links (invite_code) where status = 'pending';

create index care_links_caregiver_active on care_links (caregiver_id, patient_id)
  where status = 'active';

alter table care_links enable row level security;

-- ---------------------------------------------------------------------------
-- the access rule
-- ---------------------------------------------------------------------------

-- Single source of truth for "may the caller touch rows belonging to
-- `target`". Security definer so it can consult care_links regardless of that
-- table's own policies; `search_path` is pinned because a security-definer
-- function that resolves names through the caller's search_path is a
-- privilege-escalation hole.
create or replace function public.can_access_user_data(target uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select target = (select auth.uid())
      or exists (
        select 1
        from public.care_links
        where status = 'active'
          and caregiver_id = (select auth.uid())
          and patient_id = target
      );
$$;

revoke execute on function public.can_access_user_data(uuid) from public;
grant execute on function public.can_access_user_data(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- policies
-- ---------------------------------------------------------------------------

drop policy "medicines_owner_all" on medicines;
drop policy "schedules_owner_all" on schedules;
drop policy "dose_logs_owner_all" on dose_logs;

-- `with check` matters as much as `using` here: it is what lets a caregiver
-- insert a medicine carrying the *parent's* user_id, and what stops anyone
-- writing a row onto an account they are not linked to.
create policy "medicines_access" on medicines
  for all using (public.can_access_user_data(user_id))
  with check (public.can_access_user_data(user_id));

create policy "schedules_access" on schedules
  for all using (public.can_access_user_data(user_id))
  with check (public.can_access_user_data(user_id));

create policy "dose_logs_access" on dose_logs
  for all using (public.can_access_user_data(user_id))
  with check (public.can_access_user_data(user_id));

-- A profile is readable by its owner and by anyone allowed to act for them,
-- so the caregiver can show the parent's name. Writable only by its owner —
-- a caregiver has no business renaming someone.
create policy "profiles_read" on profiles
  for select using (
    public.can_access_user_data(user_id)
    or exists (
      select 1 from care_links
      where status = 'active'
        and patient_id = (select auth.uid())
        and caregiver_id = profiles.user_id
    )
  );

create policy "profiles_write_own" on profiles
  for all using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- Read only the links you are actually part of. Note there is no policy that
-- lets anyone search by invite_code — claiming goes through the function
-- below, so an unclaimed invite is invisible to everyone but its issuer.
create policy "care_links_read_own" on care_links
  for select using (
    patient_id = (select auth.uid()) or caregiver_id = (select auth.uid())
  );

-- Every state change goes through the functions below, which enforce who is
-- allowed to make it. Deliberately no insert/update/delete policy: without
-- one, direct writes are refused and the functions are the only way in.

-- ---------------------------------------------------------------------------
-- link lifecycle
-- ---------------------------------------------------------------------------

-- Six digits, drawn from pgcrypto rather than random(). The code is not the
-- security boundary — the parent's confirmation is — but it should not be
-- predictable from another code issued moments earlier.
create or replace function public.generate_invite_code()
returns text
language sql
volatile
as $$
  select lpad((
    (get_byte(b, 0)::int * 65536 + get_byte(b, 1)::int * 256 + get_byte(b, 2)::int) % 1000000
  )::text, 6, '0')
  from (select gen_random_bytes(3) as b) s;
$$;

-- Issues an invite for the caller as patient. Replaces any invite they have
-- not yet completed, so "show me the code" is always safe to tap again.
create or replace function public.create_care_invite()
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := (select auth.uid());
  code text;
begin
  if me is null then
    raise exception 'not_authenticated';
  end if;

  if exists (select 1 from care_links where patient_id = me and status = 'active') then
    raise exception 'already_linked';
  end if;
  if exists (select 1 from care_links where caregiver_id = me and status <> 'revoked') then
    raise exception 'already_a_caregiver';
  end if;

  -- Supersede an outstanding invite rather than colliding with the
  -- one-live-link index.
  update care_links
     set status = 'revoked', revoked_at = now()
   where patient_id = me and status in ('pending', 'claimed');

  code := public.generate_invite_code();

  insert into care_links (patient_id, status, invite_code, expires_at)
  values (me, 'pending', code, now() + interval '15 minutes');

  return code;
end;
$$;

-- Claims an invite as the caregiver. Succeeding does *not* grant access —
-- the link sits in 'claimed' until the patient confirms who it is.
create or replace function public.claim_care_invite(code text)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := (select auth.uid());
  link care_links;
begin
  if me is null then
    raise exception 'not_authenticated';
  end if;

  if exists (select 1 from care_links where caregiver_id = me and status <> 'revoked') then
    raise exception 'already_a_caregiver';
  end if;
  if exists (select 1 from care_links where patient_id = me and status <> 'revoked') then
    raise exception 'already_a_patient';
  end if;

  select * into link
    from care_links
   where invite_code = code
     and status = 'pending'
     and expires_at > now()
   for update;

  if link is null then
    -- One message for "wrong code" and "expired code" alike: telling them
    -- apart would confirm to a guesser that a code exists.
    raise exception 'invalid_or_expired_code';
  end if;
  if link.patient_id = me then
    raise exception 'cannot_link_to_self';
  end if;

  update care_links
     set caregiver_id = me,
         status = 'claimed',
         claimed_at = now(),
         invite_code = null
   where id = link.id;

  return link.id;
end;
$$;

-- The consent step. Only the patient can call it, and only they can turn a
-- claimed link into a live one.
create or replace function public.confirm_care_link(link_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := (select auth.uid());
  updated int;
begin
  if me is null then
    raise exception 'not_authenticated';
  end if;

  update care_links
     set status = 'active', accepted_at = now(), expires_at = null
   where id = link_id
     and patient_id = me
     and status = 'claimed';

  get diagnostics updated = row_count;
  if updated = 0 then
    raise exception 'no_link_to_confirm';
  end if;
end;
$$;

-- Either side can end it, at any point in the lifecycle, and doing so frees
-- both of them to pair with someone else.
create or replace function public.revoke_care_link(link_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := (select auth.uid());
  updated int;
begin
  if me is null then
    raise exception 'not_authenticated';
  end if;

  update care_links
     set status = 'revoked', revoked_at = now(), invite_code = null
   where id = link_id
     and status <> 'revoked'
     and (patient_id = me or caregiver_id = me);

  get diagnostics updated = row_count;
  if updated = 0 then
    raise exception 'no_link_to_revoke';
  end if;
end;
$$;

revoke execute on function public.create_care_invite() from public;
revoke execute on function public.claim_care_invite(text) from public;
revoke execute on function public.confirm_care_link(uuid) from public;
revoke execute on function public.revoke_care_link(uuid) from public;
revoke execute on function public.generate_invite_code() from public;

grant execute on function public.create_care_invite() to authenticated;
grant execute on function public.claim_care_invite(text) to authenticated;
grant execute on function public.confirm_care_link(uuid) to authenticated;
grant execute on function public.revoke_care_link(uuid) to authenticated;
