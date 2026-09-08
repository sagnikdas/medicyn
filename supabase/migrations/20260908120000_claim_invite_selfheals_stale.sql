-- An expired, unconfirmed 'claimed' row was never a permanent ticket, but
-- nothing ever moved it out of that status once its 15-minute confirmation
-- window (20260819161000_claimed_link_expiry.sql) passed. claim_care_invite
-- and create_care_invite both guard against a double relationship with
-- `status <> 'revoked'`, which matches a stale expired row exactly as if it
-- were live -- so a caregiver whose claim timed out unconfirmed could never
-- claim another invite again, with any patient, without an operator
-- manually revoking the dead row. The reverse (a patient whose own pending
-- invite went unclaimed for 15 minutes) hit the same wall.
--
-- Fix: self-heal on the way in. Before either guard runs, revoke the
-- caller's own expired 'pending'/'claimed' rows -- the same "supersede a
-- stale attempt" idea create_care_invite already used for a live invite,
-- just extended to cover both role columns and both of the statuses that
-- carry an expires_at. 'active' has no expiry and 'revoked' is already
-- excluded by the guards, so neither needs touching here.
--
-- This does not add a periodic sweep for a row nobody ever retries against
-- -- only the next actual attempt (by either party) clears it. That is a
-- smaller residual gap than a permanent lockout and can be closed later
-- with a scheduled job if it turns out to matter in practice.

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

  update care_links
     set status = 'revoked', revoked_at = now()
   where (patient_id = me or caregiver_id = me)
     and status in ('pending', 'claimed')
     and expires_at < now();

  if exists (select 1 from care_links where patient_id = me and status = 'active') then
    raise exception 'already_linked';
  end if;
  if exists (select 1 from care_links where caregiver_id = me and status <> 'revoked') then
    raise exception 'already_a_caregiver';
  end if;

  -- Supersede an outstanding invite rather than colliding with the
  -- one-live-link index. Still needed for a still-valid invite the caller
  -- wants to replace -- the self-heal above only clears expired ones.
  update care_links
     set status = 'revoked', revoked_at = now()
   where patient_id = me and status in ('pending', 'claimed');

  code := public.generate_invite_code();

  insert into care_links (patient_id, status, invite_code, expires_at)
  values (me, 'pending', code, now() + interval '15 minutes');

  return code;
end;
$$;

create or replace function public.claim_care_invite(code text)
returns jsonb
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

  insert into care_invite_claim_attempts (caller_id) values (me);

  if (select count(*) from care_invite_claim_attempts
       where caller_id = me
         and attempted_at > now() - interval '15 minutes') > 10 then
    return jsonb_build_object('error', 'too_many_attempts');
  end if;

  update care_links
     set status = 'revoked', revoked_at = now()
   where (caregiver_id = me or patient_id = me)
     and status in ('pending', 'claimed')
     and expires_at < now();

  if exists (select 1 from care_links where caregiver_id = me and status <> 'revoked') then
    return jsonb_build_object('error', 'already_a_caregiver');
  end if;
  if exists (select 1 from care_links where patient_id = me and status <> 'revoked') then
    return jsonb_build_object('error', 'already_a_patient');
  end if;

  select * into link
    from care_links
   where invite_code = code
     and status = 'pending'
     and expires_at > now()
   for update;

  if link is null then
    return jsonb_build_object('error', 'invalid_or_expired_code');
  end if;
  if link.patient_id = me then
    return jsonb_build_object('error', 'cannot_link_to_self');
  end if;

  update care_links
     set caregiver_id = me,
         status = 'claimed',
         claimed_at = now(),
         invite_code = null,
         expires_at = now() + interval '15 minutes'
   where id = link.id;

  return jsonb_build_object('id', link.id);
end;
$$;

comment on function public.claim_care_invite(text) is
  'Claims a pending invite as caregiver. Returns {"id": uuid} on success or {"error": code} on refusal. Self-heals the caller''s own expired pending/claimed rows before checking for an existing relationship. Does not RAISE on expected failures so the attempt ledger commits on hosted Postgres, where dblink loopback is not allowed.';
