-- Proof of possession before a device token can change owners.
--
-- `register_device_token` has always moved the row on conflict: an FCM token
-- belongs to an *install*, not an account, and a second person signing in on
-- one phone (a handed-back phone, a shared tablet) has to take the routing
-- with them. That requirement still holds. What it did not do is ask whether
-- the caller is that install. Anyone who learned the token string — a log
-- line, a backup, a support dump — could re-point it, silencing the victim
-- and drawing the attacker's care alerts onto the victim's device.
--
-- `install_id` is a UUID the app mints once and keeps locally. Matching it is
-- what distinguishes "I am the phone that already holds this token" from "I
-- merely know the token". A stale-only window (`refreshed_at` older than N)
-- cannot do that job: a handed-back phone whose unregister-on-sign-out failed
-- still has a fresh timestamp, and would then be stuck.
--
-- Existing production rows have no install_id. The null arm below lets the
-- first caller after this migration claim such a row and write the id; after
-- that the row is possessed like any other. That is a one-time back-compat
-- hole, not an ongoing takeover path.
--
-- Postgres cannot CREATE OR REPLACE a function onto a different argument
-- list, so the two-argument form is dropped and the three-argument form is
-- created in its place.

alter table public.device_tokens
  add column install_id text;

drop function public.register_device_token(text, text);

create function public.register_device_token(
  p_token text,
  p_platform text,
  p_install_id text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := (select auth.uid());
  affected int;
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
  if p_install_id is null or length(p_install_id) = 0 then
    raise exception 'invalid_install_id';
  end if;

  insert into device_tokens (token, user_id, platform, install_id, refreshed_at)
  values (p_token, me, p_platform, p_install_id, now())
  on conflict (token) do update
    set user_id = excluded.user_id,
        platform = excluded.platform,
        install_id = excluded.install_id,
        refreshed_at = now()
    where
      -- Own refresh. Also the path that stamps install_id onto an old row
      -- the same account is still holding.
      device_tokens.user_id = excluded.user_id
      -- Same physical install, second account: the handed-back phone.
      or (
        device_tokens.install_id is not distinct from excluded.install_id
        and device_tokens.install_id is not null
      )
      -- One-time back-compat: a pre-migration row has nothing to match.
      -- The update writes install_id, so this arm cannot fire again.
      or device_tokens.install_id is null;

  get diagnostics affected = row_count;
  if affected = 0 then
    raise exception 'token_not_possessed';
  end if;
end;
$$;

revoke execute on function public.register_device_token(text, text, text) from public;
grant execute on function public.register_device_token(text, text, text) to authenticated;
