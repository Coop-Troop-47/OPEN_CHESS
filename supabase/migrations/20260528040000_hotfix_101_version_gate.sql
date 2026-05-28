-- Version gate update for Open Chess 1.0.1 hotfix.

insert into public.app_version_gate (
  id,
  latest_version,
  minimum_supported_version,
  download_url,
  release_notes
)
values (
  true,
  '1.0.1',
  '1.0.1',
  'https://raw.githubusercontent.com/Coop-Troop-47/OPEN_CHESS/main/chess_client.html',
  '- Fixed ranked rematch settings so colour and handicaps cannot be changed.
- Fixed premove selection so only legal premove destinations are shown and accepted.
- Reduced notation arrow overdraw and refined captured-piece glow.
- Added in-game bug reporting, version display, and cleaner player-name layout.
- Removed extra draw/resignation popups when the board result animation already plays.'
)
on conflict (id) do update
set latest_version = excluded.latest_version,
    minimum_supported_version = excluded.minimum_supported_version,
    download_url = excluded.download_url,
    release_notes = excluded.release_notes,
    updated_at = now();
