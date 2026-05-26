delete from storage.objects o
using public.profiles p
where o.bucket_id = 'avatars'
  and o.name like p.id::text || '/%'
  and p.username ~ '^player_[a-f0-9]{12}$'
  and not exists (
    select 1
    from public.ranked_games g
    where g.white_id = p.id or g.black_id = p.id
  );

delete from auth.users u
using public.profiles p
where u.id = p.id
  and p.username ~ '^player_[a-f0-9]{12}$'
  and not exists (
    select 1
    from public.ranked_games g
    where g.white_id = p.id or g.black_id = p.id
  );

update public.profiles
set display_name = username
where display_name is distinct from username;

create or replace function public.sync_single_public_name()
returns trigger
language plpgsql
as $$
begin
  new.display_name := new.username;
  return new;
end;
$$;

drop trigger if exists profiles_sync_single_public_name on public.profiles;
create trigger profiles_sync_single_public_name
before insert or update on public.profiles
for each row execute function public.sync_single_public_name();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  requested_username text;
begin
  requested_username := substr(
    regexp_replace(coalesce(new.raw_user_meta_data->>'username', ''), '[^A-Za-z0-9_]', '_', 'g'),
    1,
    24
  );

  if length(requested_username) < 3 then
    raise exception 'Username must be 3-24 letters, numbers, or underscores';
  end if;

  if exists (
    select 1
    from public.profiles
    where username = requested_username
  ) then
    raise exception 'Username is already taken';
  end if;

  insert into public.profiles (id, username, display_name)
  values (new.id, requested_username, requested_username);

  return new;
end;
$$;
