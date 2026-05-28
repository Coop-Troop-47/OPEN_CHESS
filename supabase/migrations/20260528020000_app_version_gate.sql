-- Manual Supabase SQL for client version gating.
-- Run this in Supabase SQL Editor. Safe to rerun.
-- Increase minimum_supported_version when older local HTML files must be blocked from online features.

create table if not exists public.app_version_gate (
  id boolean primary key default true,
  latest_version text not null,
  minimum_supported_version text not null,
  download_url text not null,
  release_notes text,
  updated_at timestamptz not null default now(),
  constraint app_version_gate_singleton check (id)
);

alter table public.app_version_gate enable row level security;

drop policy if exists "App version gate is public readable" on public.app_version_gate;
create policy "App version gate is public readable"
on public.app_version_gate for select
using (true);

insert into public.app_version_gate (
  id,
  latest_version,
  minimum_supported_version,
  download_url,
  release_notes
)
values (
  true,
  '0.5.0',
  '0.5.0',
  'https://raw.githubusercontent.com/Coop-Troop-47/OPEN_CHESS/main/chess_client.html',
  'Initial server-backed client version gate.'
)
on conflict (id) do update
set latest_version = excluded.latest_version,
    minimum_supported_version = excluded.minimum_supported_version,
    download_url = excluded.download_url,
    release_notes = excluded.release_notes,
    updated_at = now();

