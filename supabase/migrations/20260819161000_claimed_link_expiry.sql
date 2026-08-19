-- A claimed care link is not a permanent ticket to confirmation.
--
-- `claim_care_invite` already refused a pending invite whose `expires_at`
-- had passed, but then left that timestamp alone — so a code claimed at
-- minute 14 of its window kept a few seconds of leftover invite expiry, and
-- a code claimed at minute 1 sat in `claimed` indefinitely. `confirm_care_link`
-- matched only on id, patient, and status, so the parent's confirmation
-- could arrive days later. The UI promises codes last 15 minutes; that
-- bound has to cover the claimed state too.
--
-- Claim now stamps a fresh 15-minute window. Confirm refuses a claimed row
-- whose window has closed. An active link still has no expiry.

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
         invite_code = null,
         expires_at = now() + interval '15 minutes'
   where id = link.id;

  return link.id;
end;
$$;

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
     and status = 'claimed'
     and expires_at > now();

  get diagnostics updated = row_count;
  if updated = 0 then
    raise exception 'no_link_to_confirm';
  end if;
end;
$$;
