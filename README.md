# Open Chess

Open Chess is a local-first single-file chess app with optional Supabase-backed accounts, profiles, avatars, ratings, and leaderboard data.

## Run

You can open `chess_client.html` directly.

For the smoothest auth redirect experience, you can also run it through a tiny local server:

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

Supabase email confirmations always redirect somewhere after confirming. The project is configured to use:

```text
http://localhost:5173/chess_client.html
```

as the default auth redirect, with common localhost ports allow-listed for development.

If you opened the app directly as a `file://` page, confirmation links may end on a failed localhost page. That is acceptable for this local-first app: return to the HTML file after clicking the confirmation link and sign in.
