-- Manual Supabase SQL for live presence, idempotent ranked results, and disconnect adjudication.
-- Run this in the Supabase SQL Editor before deploying the updated submit-ranked-result Edge Function.

alter table public.profiles
  add column if not exists last_seen timestamptz;

alter table public.ranked_games
  add column if not exists room_id text;

create unique index if not exists ranked_games_room_id_key
on public.ranked_games (room_id)
where room_id is not null;

create table if not exists public.ranked_live_games (
  room_id text primary key,
  white_id uuid not null references public.profiles(id) on delete cascade,
  black_id uuid not null references public.profiles(id) on delete cascade,
  white_last_seen timestamptz,
  black_last_seen timestamptz,
  white_moved boolean not null default false,
  black_moved boolean not null default false,
  status text not null default 'active',
  resolved_result text,
  ranked_game_id uuid references public.ranked_games(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ranked_live_games_different_players check (white_id <> black_id),
  constraint ranked_live_games_status_check check (status in ('active', 'resolved')),
  constraint ranked_live_games_result_check check (resolved_result is null or resolved_result in ('white', 'black', 'draw', 'aborted'))
);

alter table public.ranked_live_games enable row level security;

drop policy if exists "Ranked live games visible to participants" on public.ranked_live_games;
create policy "Ranked live games visible to participants"
on public.ranked_live_games for select
using (auth.uid() = white_id or auth.uid() = black_id);

drop policy if exists "Ranked live games insertable by participants" on public.ranked_live_games;
create policy "Ranked live games insertable by participants"
on public.ranked_live_games for insert
with check (auth.uid() = white_id or auth.uid() = black_id);

drop policy if exists "Ranked live games updatable by participants" on public.ranked_live_games;
create policy "Ranked live games updatable by participants"
on public.ranked_live_games for update
using (auth.uid() = white_id or auth.uid() = black_id)
with check (auth.uid() = white_id or auth.uid() = black_id);

create or replace function public.touch_profile_presence()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  update public.profiles
  set last_seen = now()
  where id = auth.uid();
end;
$$;

create or replace function public.touch_ranked_live_game(
  p_room_id text,
  p_white_id uuid,
  p_black_id uuid,
  p_white_moved boolean default false,
  p_black_moved boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  actor uuid := auth.uid();
  row public.ranked_live_games%rowtype;
begin
  if actor is null then
    raise exception 'Not authenticated';
  end if;
  if actor <> p_white_id and actor <> p_black_id then
    raise exception 'Only a participant can update this ranked game';
  end if;
  if p_white_id = p_black_id then
    raise exception 'A ranked game requires two different players';
  end if;

  insert into public.ranked_live_games (
    room_id,
    white_id,
    black_id,
    white_last_seen,
    black_last_seen,
    white_moved,
    black_moved
  )
  values (
    p_room_id,
    p_white_id,
    p_black_id,
    case when actor = p_white_id then now() else null end,
    case when actor = p_black_id then now() else null end,
    coalesce(p_white_moved, false),
    coalesce(p_black_moved, false)
  )
  on conflict (room_id) do update
  set
    white_last_seen = case when actor = excluded.white_id then now() else ranked_live_games.white_last_seen end,
    black_last_seen = case when actor = excluded.black_id then now() else ranked_live_games.black_last_seen end,
    white_moved = ranked_live_games.white_moved or excluded.white_moved,
    black_moved = ranked_live_games.black_moved or excluded.black_moved,
    updated_at = now()
  returning * into row;

  return jsonb_build_object('live_game_id', row.room_id, 'status', row.status);
end;
$$;

create or replace function public.record_ranked_result_once(
  p_room_id text,
  p_white_id uuid,
  p_black_id uuid,
  p_result text,
  p_result_reason text default 'normal',
  p_pgn text default null,
  p_final_fen text default null,
  p_time_control text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  existing public.ranked_games%rowtype;
  recorded jsonb;
  recorded_game_id uuid;
begin
  if p_room_id is not null then
    perform pg_advisory_xact_lock(hashtext(p_room_id));
  end if;

  if p_room_id is not null then
    select * into existing from public.ranked_games where room_id = p_room_id;
    if existing.id is not null then
      return jsonb_build_object(
        'game_id', existing.id,
        'result', existing.result,
        'duplicate', true,
        'white_rating_after', existing.white_rating_after,
        'black_rating_after', existing.black_rating_after
      );
    end if;
  end if;

  recorded := public.record_ranked_result(
    p_white_id,
    p_black_id,
    p_result,
    p_result_reason,
    p_pgn,
    p_final_fen,
    p_time_control
  );

  if p_room_id is not null then
    recorded_game_id := (recorded ->> 'game_id')::uuid;
    update public.ranked_games
    set room_id = p_room_id
    where id = recorded_game_id;

    update public.ranked_live_games
    set status = 'resolved',
        resolved_result = p_result,
        ranked_game_id = recorded_game_id,
        updated_at = now()
    where room_id = p_room_id;
  end if;

  return recorded || jsonb_build_object('result', p_result, 'duplicate', false);
end;
$$;

create or replace function public.resolve_ranked_disconnect(
  p_room_id text,
  p_reporter_id uuid,
  p_pgn text default null,
  p_final_fen text default null,
  p_time_control text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  live public.ranked_live_games%rowtype;
  stale_after interval := interval '20 seconds';
  white_stale boolean;
  black_stale boolean;
  result text;
begin
  select * into live
  from public.ranked_live_games
  where room_id = p_room_id
  for update;

  if live.room_id is null then
    raise exception 'Ranked live game was not found';
  end if;

  if p_reporter_id <> live.white_id and p_reporter_id <> live.black_id then
    raise exception 'Only a participant can resolve this ranked game';
  end if;

  if live.status = 'resolved' then
    return jsonb_build_object(
      'game_id', live.ranked_game_id,
      'result', live.resolved_result,
      'duplicate', true
    );
  end if;

  white_stale := live.white_last_seen is null or live.white_last_seen < now() - stale_after;
  black_stale := live.black_last_seen is null or live.black_last_seen < now() - stale_after;

  result := case
    when white_stale and black_stale then 'aborted'
    when white_stale and live.white_moved then 'black'
    when black_stale and live.black_moved then 'white'
    when white_stale or black_stale then 'aborted'
    else 'aborted'
  end;

  return public.record_ranked_result_once(
    p_room_id,
    live.white_id,
    live.black_id,
    result,
    case when result = 'aborted' then 'disconnect_abort' else 'disconnect' end,
    p_pgn,
    p_final_fen,
    p_time_control
  );
end;
$$;
