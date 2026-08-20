-- Article 7 record of consent for each processing purpose.
--
-- Health data is Article 9 special-category data. The only available 9(2)
-- condition is explicit consent, and Art. 7(1) requires that we be able to
-- demonstrate it. One row per (user, purpose) is the current state — mutated
-- on grant and withdraw — not a full audit log. granted_at is the time of
-- the latest grant; withdrawn_at is null while the purpose is currently
-- granted.
--
-- SELECT is own-rows only. A caregiver must not read the patient's consents,
-- which is why this does not go through can_access_user_data(). There are
-- no insert/update/delete policies: every write goes through record_consent.

create table public.consents (
  user_id uuid not null references auth.users (id) on delete cascade,
  purpose text not null,
  granted_at timestamptz,
  withdrawn_at timestamptz,
  policy_version text not null,
  consent_text_hash text not null,
  app_version text,
  updated_at timestamptz not null default now(),
  primary key (user_id, purpose),
  constraint consents_purpose_check check (
    purpose in ('cloud_backup', 'anthropic_parse', 'google_speech', 'care_share')
  )
);

alter table public.consents enable row level security;

create policy consents_select_own on public.consents
  for select
  using ((select auth.uid()) = user_id);

create function public.record_consent(
  p_purpose text,
  p_granted boolean,
  p_policy_version text,
  p_consent_text_hash text,
  p_app_version text
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
  if p_purpose not in ('cloud_backup', 'anthropic_parse', 'google_speech', 'care_share') then
    raise exception 'invalid_purpose';
  end if;
  if p_granted is null then
    raise exception 'invalid_granted';
  end if;
  if p_policy_version is null or length(p_policy_version) = 0 then
    raise exception 'invalid_policy_version';
  end if;
  if p_consent_text_hash is null or length(p_consent_text_hash) = 0 then
    raise exception 'invalid_consent_text_hash';
  end if;

  insert into consents (
    user_id,
    purpose,
    granted_at,
    withdrawn_at,
    policy_version,
    consent_text_hash,
    app_version,
    updated_at
  )
  values (
    me,
    p_purpose,
    case when p_granted then now() else null end,
    case when p_granted then null else now() end,
    p_policy_version,
    p_consent_text_hash,
    p_app_version,
    now()
  )
  on conflict (user_id, purpose) do update
    set granted_at = case
          when p_granted then now()
          else consents.granted_at
        end,
        withdrawn_at = case
          when p_granted then null
          else now()
        end,
        policy_version = excluded.policy_version,
        consent_text_hash = excluded.consent_text_hash,
        app_version = excluded.app_version,
        updated_at = now();
end;
$$;

revoke execute on function public.record_consent(text, boolean, text, text, text) from public;
grant execute on function public.record_consent(text, boolean, text, text, text) to authenticated;
