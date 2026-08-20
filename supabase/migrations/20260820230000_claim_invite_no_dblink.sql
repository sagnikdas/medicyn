-- Claiming a care-link code used dblink so a failed guess still counted
-- after RAISE rolled back the function's own INSERT. On hosted Postgres the
-- function does not run as a superuser, so dblink_exec refuses the loopback
-- ("password or GSSAPI delegated credentials required") and every claim —
-- including a correct, unexpired code — dies before the row is updated.
--
-- Return the outcome as jsonb instead of raising. The attempt row and the
-- claim then commit together, failed guesses still fill the ledger, and the
-- client maps `error` the same way it used to map the exception message.

drop function if exists public.claim_care_invite(text);

create function public.claim_care_invite(code text)
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
  'Claims a pending invite as caregiver. Returns {"id": uuid} on success or {"error": code} on refusal. Does not RAISE on expected failures so the attempt ledger commits on hosted Postgres, where dblink loopback is not allowed.';

revoke all on function public.claim_care_invite(text) from public;
grant execute on function public.claim_care_invite(text) to authenticated;

do $g$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke all on function public.claim_care_invite(text) from anon;
  end if;
end;
$g$;
