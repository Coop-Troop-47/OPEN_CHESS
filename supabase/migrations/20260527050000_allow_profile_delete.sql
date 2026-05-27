-- Enable users to delete their own profile row, which triggers auth user deletion via on_profile_deleted trigger
create policy "Users can delete their own profile"
on public.profiles for delete
using (auth.uid() = id);
