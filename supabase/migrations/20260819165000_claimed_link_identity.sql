-- Confirmation has to name the person it is asking about, and claiming a
-- code has to be expensive enough that guessing is not a strategy.
--
-- The parent's confirm prompt used to read the claimant through `profiles`,
-- but `profiles_read` only opens for an *active* link. At the moment of
-- consent the row is still `claimed`, so the select was empty and the UI
-- fell back to "Someone". This RPC is a deliberate one-row disclosure for
-- that moment only: display name and email, and only to the patient of that
-- claimed link. It does not widen `profiles_read`.
--
-- Separately, invite codes were six digits with no per-caller cap on
-- `claim_care_invite`. A signed-in account could sweep a live code in one
-- 15-minute window. Codes are now eight digits, and every claim attempt is
-- counted — successes and failures alike, so the counter is not an oracle.

-- ---------------------------------------------------------------------------
-- claimant identity
-- ---------------------------------------------------------------------------

create or replace function public.claimed_care_link_claimant(link_id uuid)
returns table (display_name text, email text)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p.display_name, u.email
    from public.care_links cl
    join auth.users u on u.id = cl.caregiver_id
    left join public.profiles p on p.user_id = cl.caregiver_id
   where cl.id = link_id
     and cl.patient_id = (select auth.uid())
     and cl.status = 'claimed';
$$;

revoke execute on function public.claimed_care_link_claimant(uuid) from public;
grant execute on function public.claimed_care_link_claimant(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- claim attempt ledger
-- ---------------------------------------------------------------------------
-- Written only by `claim_care_invite`. RLS is on and there is no client
-- policy: a forgotten grant cannot become an open table, and a select-own
-- policy would only tell a guesser how close they are to the cap.

create table care_invite_claim_attempts (
  caller_id uuid not null,
  attempted_at timestamptz not null default now()
);

create index care_invite_claim_attempts_caller_window
  on care_invite_claim_attempts (caller_id, attempted_at);

alter table care_invite_claim_attempts enable row level security;

-- A RAISE in this function aborts its statement, which would roll back a
-- normal INSERT and leave failed guesses uncounted. dblink writes the row
-- on a second connection so the ledger survives `invalid_or_expired_code`
-- and `too_many_attempts` alike. Without that, the cap would only apply to
-- successful claims and a brute-force sweep would never hit it.
create schema if not exists extensions;
create extension if not exists dblink with schema extensions;

-- ---------------------------------------------------------------------------
-- eight-digit codes
-- ---------------------------------------------------------------------------
-- Same construction as before: eight hex chars of a v4 UUID, interpreted as
-- a 32-bit integer, reduced into the new keyspace. Still not security
-- definer — this is a helper, not an entry point.

create or replace function public.generate_invite_code()
returns text
language sql
volatile
set search_path = pg_catalog, pg_temp
as $$
  select lpad((
    abs(('x' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))::bit(32)::int::bigint)
      % 100000000
  )::text, 8, '0');
$$;

-- ---------------------------------------------------------------------------
-- claim, with a per-caller cap
-- ---------------------------------------------------------------------------
-- Behaviour of a successful claim is unchanged from
-- `20260819161000_claimed_link_expiry.sql`: a fresh 15-minute `expires_at`
-- is stamped, and every existing refusal (already_a_caregiver,
-- already_a_patient, invalid_or_expired_code, cannot_link_to_self) still
-- fires after the rate limit. Confirm is not replaced.

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

  perform extensions.dblink_exec(
    format('dbname=%s', current_database()),
    format(
      'insert into public.care_invite_claim_attempts (caller_id) values (%L::uuid)',
      me
    )
  );

  if (select count(*) from care_invite_claim_attempts
       where caller_id = me
         and attempted_at > now() - interval '15 minutes') > 10 then
    raise exception 'too_many_attempts';
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
         invite_code = null,
         expires_at = now() + interval '15 minutes'
   where id = link.id;

  return link.id;
end;
$$;
