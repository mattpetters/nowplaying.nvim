# Hermes integration

Goodies for [Hermes](https://hermes-agent.nousresearch.com) users — slash commands and skills that complement the Neovim plugin and the standalone TUI/CLI by living right inside your AI agent.

## What's here

```
hermes/
└── skills/
    └── nowplaying/
        └── SKILL.md      # /nowplaying <subcommand>
```

Each subdirectory under `skills/` is a Hermes skill. When installed, Hermes auto-discovers it and exposes it as `/<skill-name>` slash command in the CLI, gateway, and TUI.

## Install

From the repo root:

```bash
make hermes-install
```

This symlinks `hermes/skills/<name>/` into `~/.hermes/skills/<name>/`. Edits flow through this repo's normal git workflow — the symlink keeps `~/.hermes/skills/` lightweight and the source of truth versioned.

To uninstall:

```bash
make hermes-uninstall
```

Only removes symlinks created by us — never touches a real directory or someone else's skill.

## Skills

### `/nowplaying`

Quick actions on your currently playing Spotify track. Subcommands:

| Invocation | Action |
|---|---|
| `/nowplaying` or `/nowplaying np` | Show what's playing |
| `/nowplaying like` (aliases: `love`, `save`, `<3`, `+`) | Save current track to Liked Songs |
| `/nowplaying unlike` | Remove from Liked Songs |
| `/nowplaying album` | Save the entire album to your library |
| `/nowplaying unalbum` | Remove from saved albums |
| `/nowplaying stats [week\|month]` | Listening snapshot (best-effort — Spotify API caps history at ~50 plays, see SKILL.md for details) |
| `/nowplaying help` | Show this table |

Requires the Hermes Spotify toolset (`hermes auth spotify`). The skill is read-only on `np`/`stats` and library-mutating on `like`/`unlike`/`album`/`unalbum` — none of those need an active playback device.

## Roadmap

- `/nowplaying queue <query>` — search and queue without leaving the agent
- `/nowplaying scrobble` — best-effort last.fm bridge for the data Spotify won't give us
- Apple Music parity once the standalone CLI grows a non-Spotify backend
