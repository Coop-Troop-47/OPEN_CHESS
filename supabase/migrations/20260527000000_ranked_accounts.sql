create extension if not exists "pgcrypto";

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique,
  display_name text,
  avatar_url text,
  rating integer not null default 1200 check (rating >= 100),
  wins integer not null default 0 check (wins >= 0),
  losses integer not null default 0 check (losses >= 0),
  draws integer not null default 0 check (draws >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint username_format check (username ~ '^[A-Za-z0-9_]{3,24}$')
);

create table public.ranked_games (
  id uuid primary key default gen_random_uuid(),
  white_id uuid not null references public.profiles(id) on delete restrict,
  black_id uuid not null references public.profiles(id) on delete restrict,
  winner_id uuid references public.profiles(id) on delete restrict,
  result text not null check (result in ('white','black','draw','aborted')),
  result_reason text not null default 'normal',
  pgn text,
  final_fen text,
  time_control text,
  white_rating_before integer not null,
  black_rating_before integer not null,
  white_rating_after integer not null,
  black_rating_after integer not null,
  created_at timestamptz not null default now(),
  constraint winner_matches_result check (
    (result = 'white' and winner_id = white_id) or
    (result = 'black' and winner_id = black_id) or
    (result in ('draw','aborted') and winner_id is null)
  ),
  constraint different_players check (white_id <> black_id)
);

create table public.rating_events (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.ranked_games(id) on delete cascade,
  player_id uuid not null references public.profiles(id) on delete cascade,
  opponent_id uuid not null references public.profiles(id) on delete cascade,
  rating_before integer not null,
  rating_after integer not null,
  rating_delta integer generated always as (rating_after - rating_before) stored,
  result text not null check (result in ('win','loss','draw','aborted')),
  created_at timestamptz not null default now()
);

create table public.ranked_match_invites (
  id uuid primary key default gen_random_uuid(),
  host_id uuid not null references public.profiles(id) on delete cascade,
  guest_id uuid references public.profiles(id) on delete cascade,
  status text not null default 'open' check (status in ('open','accepted','cancelled','expired')),
  time_control text not null default '10+0',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index profiles_rating_idx on public.profiles (rating desc, wins desc, username asc);
create index ranked_games_white_idx on public.ranked_games (white_id, created_at desc);
create index ranked_games_black_idx on public.ranked_games (black_id, created_at desc);
create index rating_events_player_idx on public.rating_events (player_id, created_at desc);
create index ranked_match_invites_status_idx on public.ranked_match_invites (status, created_at desc);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create trigger ranked_match_invites_set_updated_at
before update on public.ranked_match_invites
for each row execute function public.set_updated_at();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    'player_' || substr(replace(new.id::text, '-', ''), 1, 12),
    coalesce(new.raw_user_meta_data->>'display_name', new.raw_user_meta_data->>'name')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

create or replace function public.protect_ranked_profile_fields()
returns trigger
language plpgsql
as $$
begin
  if auth.role() <> 'service_role'
    and (
      new.rating is distinct from old.rating
      or new.wins is distinct from old.wins
      or new.losses is distinct from old.losses
      or new.draws is distinct from old.draws
    )
  then
    raise exception 'Ranked profile fields can only be updated server-side';
  end if;
  return new;
end;
$$;

create trigger profiles_protect_ranked_fields
before update on public.profiles
for each row execute function public.protect_ranked_profile_fields();

create or replace function public.record_ranked_result(
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
  white_profile public.profiles%rowtype;
  black_profile public.profiles%rowtype;
  white_expected numeric;
  black_expected numeric;
  white_score numeric;
  black_score numeric;
  white_after integer;
  black_after integer;
  winner uuid;
  game_id uuid;
begin
  if p_white_id = p_black_id then
    raise exception 'A ranked game requires two different players';
  end if;

  if p_result not in ('white', 'black', 'draw', 'aborted') then
    raise exception 'Invalid result';
  end if;

  select * into white_profile from public.profiles where id = p_white_id for update;
  select * into black_profile from public.profiles where id = p_black_id for update;

  if white_profile.id is null or black_profile.id is null then
    raise exception 'Both players need profiles before ranked games can be submitted';
  end if;

  white_score := case when p_result = 'white' then 1 when p_result = 'draw' then 0.5 else 0 end;
  black_score := case when p_result = 'black' then 1 when p_result = 'draw' then 0.5 else 0 end;
  white_expected := 1 / (1 + power(10, (black_profile.rating - white_profile.rating)::numeric / 400));
  black_expected := 1 / (1 + power(10, (white_profile.rating - black_profile.rating)::numeric / 400));

  white_after := case
    when p_result = 'aborted' then white_profile.rating
    else greatest(100, round(white_profile.rating + 32 * (white_score - white_expected))::integer)
  end;
  black_after := case
    when p_result = 'aborted' then black_profile.rating
    else greatest(100, round(black_profile.rating + 32 * (black_score - black_expected))::integer)
  end;

  winner := case
    when p_result = 'white' then p_white_id
    when p_result = 'black' then p_black_id
    else null
  end;

  insert into public.ranked_games (
    white_id,
    black_id,
    winner_id,
    result,
    result_reason,
    pgn,
    final_fen,
    time_control,
    white_rating_before,
    black_rating_before,
    white_rating_after,
    black_rating_after
  )
  values (
    p_white_id,
    p_black_id,
    winner,
    p_result,
    coalesce(p_result_reason, 'normal'),
    p_pgn,
    p_final_fen,
    p_time_control,
    white_profile.rating,
    black_profile.rating,
    white_after,
    black_after
  )
  returning id into game_id;

  update public.profiles
  set
    rating = white_after,
    wins = wins + case when p_result = 'white' then 1 else 0 end,
    losses = losses + case when p_result = 'black' then 1 else 0 end,
    draws = draws + case when p_result = 'draw' then 1 else 0 end
  where id = p_white_id;

  update public.profiles
  set
    rating = black_after,
    wins = wins + case when p_result = 'black' then 1 else 0 end,
    losses = losses + case when p_result = 'white' then 1 else 0 end,
    draws = draws + case when p_result = 'draw' then 1 else 0 end
  where id = p_black_id;

  insert into public.rating_events (
    game_id,
    player_id,
    opponent_id,
    rating_before,
    rating_after,
    result
  )
  values
    (
      game_id,
      p_white_id,
      p_black_id,
      white_profile.rating,
      white_after,
      case when p_result = 'white' then 'win' when p_result = 'black' then 'loss' else p_result end
    ),
    (
      game_id,
      p_black_id,
      p_white_id,
      black_profile.rating,
      black_after,
      case when p_result = 'black' then 'win' when p_result = 'white' then 'loss' else p_result end
    );

  return jsonb_build_object(
    'game_id', game_id,
    'white_rating_after', white_after,
    'black_rating_after', black_after
  );
end;
$$;

alter table public.profiles enable row level security;
alter table public.ranked_games enable row level security;
alter table public.rating_events enable row level security;
alter table public.ranked_match_invites enable row level security;

create policy "Profiles are public"
on public.profiles for select
using (true);

create policy "Users can update their editable profile fields"
on public.profiles for update
using (auth.uid() = id)
with check (auth.uid() = id);

create policy "Players can read their ranked games"
on public.ranked_games for select
using (auth.uid() = white_id or auth.uid() = black_id);

create policy "Players can read their rating events"
on public.rating_events for select
using (auth.uid() = player_id);

create policy "Open invites are visible"
on public.ranked_match_invites for select
using (status = 'open' or auth.uid() = host_id or auth.uid() = guest_id);

create policy "Users can create their own invites"
on public.ranked_match_invites for insert
with check (auth.uid() = host_id);

create policy "Invite participants can update invites"
on public.ranked_match_invites for update
using (auth.uid() = host_id or auth.uid() = guest_id)
with check (auth.uid() = host_id or auth.uid() = guest_id);

insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

create policy "Avatar images are public"
on storage.objects for select
using (bucket_id = 'avatars');

create policy "Users can upload their own avatar"
on storage.objects for insert
with check (
  bucket_id = 'avatars'
  and auth.uid()::text = (storage.foldername(name))[1]
);

create policy "Users can update their own avatar"
on storage.objects for update
using (
  bucket_id = 'avatars'
  and auth.uid()::text = (storage.foldername(name))[1]
)
with check (
  bucket_id = 'avatars'
  and auth.uid()::text = (storage.foldername(name))[1]
);

create policy "Users can delete their own avatar"
on storage.objects for delete
using (
  bucket_id = 'avatars'
  and auth.uid()::text = (storage.foldername(name))[1]
);
