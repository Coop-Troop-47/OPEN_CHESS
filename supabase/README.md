# Supabase Setup

This folder is the repo-side Supabase setup for Open Chess.

## Dashboard steps

1. Open the Supabase project.
2. Go to **Deployment > Branching > GitHub Integration**.
3. Select `Coop-Troop-47/OPEN_CHESS`.
4. Set the working directory to `.`.
5. Set the production branch to `main`.

## What is included

- `profiles`: public player profile, avatar URL, ELO, wins, losses, draws.
- `ranked_games`: immutable ranked game result records.
- `rating_events`: per-player rating deltas for history.
- `ranked_match_invites`: simple open ranked challenge records.
- `avatars` storage bucket with per-user upload policies.
- `submit-ranked-result` Edge Function for server-side ELO updates.

## Security notes

The browser must only use the Supabase anon key. Never commit or paste the service-role key into client code.

The migration enables RLS and blocks browser clients from directly editing rating, wins, losses, or draws. Ranked results should go through the Edge Function.

Deployment trigger: 2026-05-26T14:58:50Z
