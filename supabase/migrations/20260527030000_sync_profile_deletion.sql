-- Trigger to delete auth.users when a public.profiles row is deleted.
-- This ensures auth.users and public.profiles stay in sync and prevents orphaned auth users.

create or replace function public.handle_deleted_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from auth.users where id = old.id;
  return old;
end;
$$;

drop trigger if exists on_profile_deleted on public.profiles;
create trigger on_profile_deleted
  after delete on public.profiles
  for each row execute function public.handle_deleted_profile();
