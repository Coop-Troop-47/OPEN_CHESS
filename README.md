# Open Chess

Open Chess is a local-first single-file chess app with optional Supabase-backed accounts, profiles, avatars, ratings, and leaderboard data.

## Run locally

Do not open `chess_client.html` directly as a `file://` URL if you want account signup or email confirmation to work. Supabase Auth needs a normal web origin to redirect back to after confirmation.

From this folder, run:

```bash
python3 -m http.server 5173
```

Then open:

```text
http://localhost:5173/chess_client.html
```

This works regardless of where the project folder lives on your machine. The folder path can be different for every user; the browser URL stays the same.

## Supabase auth redirects

The Supabase project is configured to use:

```text
http://localhost:5173/chess_client.html
```

as the default auth redirect, with common localhost ports allow-listed for development.
