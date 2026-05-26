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

  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    final_username,
    coalesce(new.raw_user_meta_data->>'display_name', final_username)
  );
  return new;
end;
$$;
