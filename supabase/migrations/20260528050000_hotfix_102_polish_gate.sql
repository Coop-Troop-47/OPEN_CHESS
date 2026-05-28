-- Version gate update for Open Chess 1.0.2 polish and resilience pass.

insert into public.app_version_gate (
  id,
  latest_version,
  minimum_supported_version,
  download_url,
  release_notes
)
values (
  true,
  '1.0.2',
  '1.0.2',
  'https://raw.githubusercontent.com/Coop-Troop-47/OPEN_CHESS/main/chess_client.html',
  '- Rebuilt the update experience with a structured changelog modal, download action, and retry controls.
- Fixed premove execution so successful premoves update the move list instead of throwing.
- Separated active peer-game transport from account-service outages so unranked games can continue when Supabase is unavailable.
- Improved mobile and small-window layout with safer board sizing, scrollable modals, and tighter room cards.
- Hardened open-challenge payload handling and locked setup controls after a room is opened.'
)
on conflict (id) do update
set latest_version = excluded.latest_version,
    minimum_supported_version = excluded.minimum_supported_version,
    download_url = excluded.download_url,
    release_notes = excluded.release_notes,
    updated_at = now();
