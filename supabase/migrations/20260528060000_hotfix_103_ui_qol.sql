-- Version gate update for Open Chess 1.0.3 UI and board QOL pass.

insert into public.app_version_gate (
  id,
  latest_version,
  minimum_supported_version,
  download_url,
  release_notes
)
values (
  true,
  '1.0.3',
  '1.0.3',
  'https://raw.githubusercontent.com/Coop-Troop-47/OPEN_CHESS/main/chess_client.html',
  '- Fixed Ranked page layout overlap and container overflow by making time controls full-width and moving the players panel to a shared lobby profile banner.
- Moved the room opened UI (waiting/share box and blockers) dynamically inside the active Play card container depending on current active mode.
- Enabled hosts to change time controls, color, and handicap settings while a room is open, dynamically announcing updates to the lobby.
- Fixed right-click arrows and circles offset to be perfectly centered inside board squares.
- Enabled right-click arrow and circle drawing during history playback review and after the game ends.
- Corrected the initial premove highlight color to align with the red color picker on load.
- Added a crisp white stroke outline around black captured pieces for high-contrast visibility on dark backgrounds.
- Added proper spacing in the Leaderboard panel beneath the standings and stats.
- Reworked the authentication page into clean, separate tabs for Sign In and Create Account.
- Updated the Board Features modal to display elements stacked 1-by-1, with shortcuts at the top, right-drag/right-click added, and keys styled with uniform borders.
- Greyed out the profile bar of disconnected/reconnecting players and prevented status text truncation.
- Implemented persistent multiplayer game storage and automatic reconnection forcing upon page reload or app reopening.
- Added state-synchronization protocol to restore FEN, PGN move history, and timers upon successful reconnection.
- Implemented a 60-second resign countdown timer for disconnections in online and ranked games, visible in both the header status and connection interrupt modals.'
)
on conflict (id) do update
set latest_version = excluded.latest_version,
    minimum_supported_version = excluded.minimum_supported_version,
    download_url = excluded.download_url,
    release_notes = excluded.release_notes,
    updated_at = now();
