-- Remove display_name from public.profiles and clean up associated triggers and functions

-- Drop the sync_single_public_name trigger and function
drop trigger if exists profiles_sync_single_public_name on public.profiles;
drop function if exists public.sync_single_public_name();

-- Remove display_name column
alter table public.profiles drop column if exists display_name;

-- Update handle_new_user function to not reference display_name
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  requested_username text;
  final_username text;
begin
  requested_username := substr(
    regexp_replace(coalesce(new.raw_user_meta_data->>'username', ''), '[^A-Za-z0-9_]', '_', 'g'),
    1,
    24
  );

  if length(requested_username) >= 3
    and not exists (
      select 1
      from public.profiles
      where username = requested_username
    )
  then
    final_username := requested_username;
  else
    final_username := 'player_' || substr(replace(new.id::text, '-', ''), 1, 12);
  end if;

  insert into public.profiles (id, username)
  values (
    new.id,
    final_username
  );
  return new;
end;
$$;
