-- Database migration for bug reporting.
-- Creates the public.bug_reports table, enables RLS, and sets version gate to 1.0.0.

create table if not exists public.bug_reports (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references auth.users(id) on delete set null,
  reporter_username text,
  description text not null,
  client_version text not null,
  browser_info text,
  created_at timestamptz not null default now()
);

alter table public.bug_reports enable row level security;

drop policy if exists "Anyone can insert bug reports" on public.bug_reports;
create policy "Anyone can insert bug reports"
on public.bug_reports for insert
with check (true);

-- Also update app_version_gate to 1.0.0
insert into public.app_version_gate (
  id,
  latest_version,
  minimum_supported_version,
  download_url,
  release_notes
)
values (
  true,
  '1.0.0',
  '1.0.0',
  'https://raw.githubusercontent.com/Coop-Troop-47/OPEN_CHESS/main/chess_client.html',
  'Version 1.0.0 release update.'
)
on conflict (id) do update
set latest_version = excluded.latest_version,
    minimum_supported_version = excluded.minimum_supported_version,
    download_url = excluded.download_url,
    release_notes = excluded.release_notes,
    updated_at = now();
