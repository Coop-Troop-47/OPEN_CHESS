# Open Chess

Open Chess is a local-first single-file chess app with optional Supabase-backed accounts, profiles, avatars, ratings, and leaderboard data.

## Run

You can open `chess_client.html` directly.

For the smoothest auth experience, you can also run it through a tiny local server:

From this folder, run:

```bash
python3 -m http.server 5173
```

Then open:

```text
http://localhost:5173/chess_client.html
```

This works regardless of where the project folder lives on your machine. The folder path can be different for every user; the browser URL stays the same.
