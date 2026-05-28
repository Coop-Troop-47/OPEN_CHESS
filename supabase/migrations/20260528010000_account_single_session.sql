-- Manual Supabase SQL for reliable single-active-session account enforcement.
-- Run after the live presence/disconnect SQL. Safe to rerun.

alter table public.profiles
  add column if not exists active_instance_id text,
  add column if not exists active_session_started_at timestamptz,
  add column if not exists active_session_seen_at timestamptz;

create or replace function public.claim_account_session(
  p_instance_id text,
  p_started_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  actor uuid := auth.uid();
  profile_row public.profiles%rowtype;
begin
  if actor is null then
    raise exception 'Not authenticated';
  end if;

  select * into profile_row
  from public.profiles
  where id = actor
  for update;

  if profile_row.id is null then
    raise exception 'Profile not found';
  end if;

  if profile_row.active_instance_id is null
     or profile_row.active_instance_id = p_instance_id
     or profile_row.active_session_started_at is null
     or profile_row.active_session_started_at <= p_started_at then
    update public.profiles
    set active_instance_id = p_instance_id,
        active_session_started_at = p_started_at,
        active_session_seen_at = now(),
        last_seen = now()
    where id = actor;

    return jsonb_build_object(
      'active', true,
      'active_instance_id', p_instance_id,
      'active_session_started_at', p_started_at
    );
  end if;

  return jsonb_build_object(
    'active', false,
    'active_instance_id', profile_row.active_instance_id,
    'active_session_started_at', profile_row.active_session_started_at
  );
end;
$$;

