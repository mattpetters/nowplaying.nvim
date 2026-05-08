---
name: nowplaying
description: Quick actions on the user's currently playing Spotify track — like/save, unlike, show now-playing, save album, and "Wrapped"-style listening stats. Invoked as `/nowplaying <subcommand>`. The first word after the slash is the subcommand; everything else is its arguments. Assumes the Hermes Spotify toolset is enabled and `hermes auth spotify` has been run. Sister project to nowplaying.nvim — lives in https://github.com/mattpetters/nowplaying.nvim under `hermes/skills/nowplaying/`.
version: 1.0.0
author: Matt Petters
license: GPL-3.0-only
prerequisites:
  tools: [spotify_playback, spotify_library, spotify_albums, spotify_search]
metadata:
  hermes:
    tags: [spotify, music, nowplaying, slash-command]
    related_skills: [spotify]
---

# /nowplaying

Slash-command goodies for the user's currently playing Spotify track. The skill body parses the first whitespace-separated word after the slash and dispatches.

## Dispatch table

| Subcommand (and aliases) | Action |
|---|---|
| (no arg), `np`, `current`, `?` | Show what's playing — title, artist, album, progress |
| `like`, `love`, `save`, `<3`, `+`, `❤️` | Save current track to user's Liked Songs |
| `unlike`, `unsave`, `remove`, `-` | Remove current track from Liked Songs |
| `album` | Save the entire album of current track |
| `unalbum` | Remove that album from saved albums |
| `stats [week\|month\|6mo\|year\|all]` | Spotify-Wrapped-style listening summary (best-effort, see Stats section) |
| `help`, `commands` | Print this dispatch table back to the user |

If the first arg matches none of these, default to `np` and gently note "didn't recognize `<arg>`, here's what's playing".

## Subcommand details

### np (default — no arg)

```
spotify_playback({"action": "get_currently_playing"})
```

If `is_playing: false` or 204/empty → "Nothing playing right now." Don't retry. Don't call `get_state` afterward — the single call has everything.

Format the response compactly (terminal-friendly, no markdown tables):

```
♪ <Title>
  <Artist 1>, <Artist 2> · <Album>
  <m:ss> / <m:ss>  on <Device or context>
```

Skip the device line if `actions.disallows.resuming` is missing — keeps it short.

### like / love / save / <3 / + / ❤️

1. `spotify_playback({"action": "get_currently_playing"})` — grab `item.uri` and `item.name` + first artist
2. `spotify_library({"kind": "tracks", "action": "save", "uris": [<uri>]})`
3. Confirm: `❤ Saved "<Title>" by <Artist> to your Liked Songs.`

If nothing is playing, tell the user. If the save call returns success but the track was already saved, Spotify's API returns 200 either way — that's fine, just confirm.

### unlike / unsave / remove / -

Mirror of `like` but with `spotify_library({"kind":"tracks", "action":"remove", ...})`. Confirm: `Removed "<Title>" by <Artist> from your Liked Songs.`

### album

1. Grab currently playing → `item.album.uri` + `item.album.name`
2. `spotify_library({"kind": "albums", "action": "save", "items": [<album_id>]})` — note: the Hermes `spotify_library` tool wants `items` (bare IDs) for albums, not `ids` and not `uris`. Strip the `spotify:album:` prefix to get the ID. Passing `ids` returns "At least one Spotify item is required."
3. Confirm: `💿 Saved album "<Album>" by <Artist> to your library.`

### unalbum

Mirror of `album` with `action: "remove"`.

### stats [period]

**Honest caveat first:** the Spotify Web API does NOT expose listening history beyond the last ~50 plays. There is no programmatic Wrapped equivalent — that data is generated server-side by Spotify and not in any public endpoint. So this subcommand can only show:

- Recently played: last 50 tracks via `spotify_playback({"action": "recently_played", "limit": 50})`
- Saved tracks added in the period: filter `spotify_library({"kind":"tracks", "action":"list", "limit":50})` by `added_at`
- Top artist/track aggregates from recently_played (count occurrences)

If the user asks for `year` or `all`, surface the limitation up front: "Spotify's API caps history at ~50 recent plays, so this is a snapshot, not real Wrapped data. For deeper analysis, last.fm scrobbling would be needed."

Period interpretation (default = `week`):
- `week` → last 7 days (filter recently_played by ISO timestamp)
- `month` → last 30 days
- `6mo`, `year`, `all` → just show last 50 plays + caveat above

Build the summary as plain text:

```
🎧 Listening snapshot · last 7 days (last 50 plays)

Top artists:
  1. <Name> — <count> plays
  2. ...

Top tracks:
  1. <Title> — <Artist> (<count>)
  2. ...

Recently saved (in window):
  • <Title> — <Artist>
  ...

Note: Spotify's API doesn't expose full listening history. For real Wrapped-style analytics across the year, scrobble to last.fm.
```

If `recently_played` returns empty, say so cleanly and skip the breakdown.

### help

Print the dispatch table from this skill verbatim (or a compact version).

## Common failure modes

- **No active device** (`403 No active device`) — only matters for actions that mutate playback. `like`/`unlike`/`album`/`np`/`stats` all work without an active device since they don't touch transport. So don't preflight-check device for those.
- **Premium required** — same: not relevant here. Library and read endpoints work on Free.
- **204 on `get_currently_playing`** — normal, means nothing playing. Tell the user, don't retry.
- **Track is a podcast episode** (`item.type === "episode"`) — `like` doesn't make sense for episodes the same way. Fall back to: "That's a podcast episode — Spotify's API doesn't support saving episodes the same way. Want me to add the show to your library instead?" then ask.

## Style

- Terminal-friendly plaintext, no markdown headings or tables. Pills/emoji are fine and welcome (`❤`, `💿`, `♪`, `🎧`).
- One-line confirmations for mutations. Short multi-line for `np` and `stats`.
- Never describe the search/lookup process — just do it and report the outcome. The user invoked a slash command; they want speed.
