-- Migration to support active game recovery without browser local storage.
-- Add host_id and is_ranked columns to ranked_live_games.

alter table public.ranked_live_games
  add column if not exists host_id uuid references public.profiles(id) on delete cascade,
  add column if not exists is_ranked boolean not null default true;

-- Update touch_ranked_live_game RPC to accept and save p_host_id and p_is_ranked.
create or replace function public.touch_ranked_live_game(
  p_room_id text,
  p_white_id uuid,
  p_black_id uuid,
  p_white_moved boolean default false,
  p_black_moved boolean default false,
  p_host_id uuid default null,
  p_is_ranked boolean default true
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
    black_moved,
    host_id,
    is_ranked
  )
  values (
    p_room_id,
    p_white_id,
    p_black_id,
    case when actor = p_white_id then now() else null end,
    case when actor = p_black_id then now() else null end,
    coalesce(p_white_moved, false),
    coalesce(p_black_moved, false),
    p_host_id,
    p_is_ranked
  )
  on conflict (room_id) do update
  set
    white_last_seen = case when actor = excluded.white_id then now() else ranked_live_games.white_last_seen end,
    black_last_seen = case when actor = excluded.black_id then now() else ranked_live_games.black_last_seen end,
    white_moved = ranked_live_games.white_moved or excluded.white_moved,
    black_moved = ranked_live_games.black_moved or excluded.black_moved,
    host_id = coalesce(ranked_live_games.host_id, excluded.host_id),
    is_ranked = excluded.is_ranked,
    updated_at = now()
  returning * into row;

  return jsonb_build_object('live_game_id', row.room_id, 'status', row.status);
end;
$$;
