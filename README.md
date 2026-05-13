<div align="center">

  <img src="./assets/nowplaying.nvim.png" height="150px">
  <h2>nowplaying 🎶</h2>
  <p>
    <a href="https://github.com/mattpetters/nowplaying.nvim/stargazers">
      <img src="https://img.shields.io/github/stars/mattpetters/nowplaying.nvim?label=Stars&style=for-the-badge&color=8b9fff" alt="GitHub stars" height="28px" />
    </a>
    <a href="https://github.com/mattpetters/nowplaying.nvim/issues">
      <img src="https://img.shields.io/github/issues/mattpetters/nowplaying.nvim?label=Issues%20open&style=for-the-badge&color=f2a17c" alt="GitHub issues" height="28px" />
    </a>
    <img src="./assets/coverage-badge.svg" alt="Coverage" height="28px" />
  </p>
  <p>A music player with multiple frontends — a standalone terminal UI and a Neovim plugin — backed by a shared daemon that handles provider polling, Spotify auth, artwork caching, and real-time audio visualization.</p>

</div>

---

## Architecture

```
                  ┌──────────────────────────────┐
                  │       nowplayingd (Go)        │
                  │  ┌──────────────────────────┐ │
     Apple Music ─┼──┤ providers                │ │
     Spotify ─────┼──┤ state machine             │ │
     Audio ───────┼──┤ artwork cache             │ │
                  │  │ token store (PKCE OAuth)   │ │
                  │  └──────────────────────────┘ │
                  │  ┌──────────────────────────┐ │
                  │  │ JSON-RPC over Unix socket │ │
                  │  └──────────┬───────────────┘ │
                  └─────────────┼─────────────────┘
                                │
              ┌─────────────────┼──────────────────┐
              │                 │                  │
         ┌────▼────┐      ┌─────▼──────┐     ┌─────▼─────┐
         │ nowplaying │     │ player.nvim │    │  future   │
         │ TUI (Go)   │     │ (Lua)       │    │  clients  │
         │ Bubble Tea │     │ Neovim      │    │           │
         └────────────┘     └─────────────┘    └───────────┘
```

**`nowplayingd`** is the single source of truth. It owns all I/O — provider polling, Spotify Web API + PKCE auth, artwork caching, and real-time audio capture with FFT spectrum analysis. Both frontends are thin clients that subscribe to the daemon's event stream and send commands over a Unix socket.

---

## Standalone TUI

The `nowplaying` binary is a full terminal music player built with [Bubble Tea](https://github.com/charmbracelet/bubbletea) and [Lip Gloss](https://github.com/charmbracelet/lipgloss).

### Visualizers

11 real-time audio visualizers, driven by FFT spectrum data captured from system audio:

| Key | Mode | Description |
|-----|------|-------------|
| default | **Equalizer** | Spectrum analyzer bars with peak-hold dots |
| | **Wave** | Scrolling sine wave |
| | **Helix** | Double-helix animation |
| | **Waterfall** | Spectrogram waterfall (scrolling down) |
| | **Radial** | Radial frequency display |
| | **Oscilloscope** | Raw waveform display |
| | **Particles** | Particle system driven by audio energy |
| | **Flame** | Fire effect with heat diffusion |
| | **iPod** | Classic click-wheel silhouette |
| | **007** | Bond-girl dancer silhouette |
| | **Erotic** | (self-explanatory) |

Press `v` to cycle through visualizers. When no real audio is available, the equalizer and other modes fall back to a simulated beat pattern.

### Themes

Press `t` to cycle themes:

- **default** — Spotify green on terminal background
- **matrix** — mactop "lime" aesthetic, sage green on black with phosphor-muted accents

### Keyboard Controls

| Key | Action |
|-----|--------|
| `space` | Play / pause |
| `n` / `p` | Next / previous track |
| `t` | Cycle theme |
| `v` | Cycle visualizer |
| `/` | Search Spotify |
| `l` | Like / unlike current track |
| `a` | Authenticate with Spotify (opens browser) |
| `q` | Quit |

### Installation

```bash
go install github.com/mattpetters/nowplaying.nvim/cmd/nowplayingd@latest
go install github.com/mattpetters/nowplaying.nvim/cmd/nowplaying@latest
```

Then run `nowplaying`. The TUI auto-spawns the daemon if it's not already running.

---

## Neovim Plugin

The original Neovim plugin (`player.nvim`) is now a thin Lua client of `nowplayingd`. It retains the responsive floating panel, Telescope-powered Spotify search, adaptive accent colors, drag & resize, and artwork rendering — but delegates all I/O to the daemon.

### Features

- Responsive floating panel with artwork, metadata, progress bar, and controls
- Draggable and resizable with mouse interaction
- Adaptive accent colors extracted from album artwork (border + background tint)
- Telescope picker for searching tracks, albums, artists, and playlists
- Playlist and album context playback (tracks continue through the list)
- Marquee scrolling statusline
- Track-change notifications via `vim.notify`
- Real artwork rendering via [image.nvim](https://github.com/3rd/image.nvim)

### Requirements

- macOS with Apple Music or Spotify installed
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (for Spotify search)
- [ImageMagick](https://imagemagick.org/) (for artwork and adaptive colors)
- [image.nvim](https://github.com/3rd/image.nvim) (for artwork in the panel)

### Installation (Lazy.nvim)

Minimal (no artwork, no Telescope):

```lua
{
  "mattpetters/nowplaying.nvim",
  config = function()
    require("player").setup()
  end,
}
```

Full setup with artwork and Telescope search:

```lua
{
  "mattpetters/nowplaying.nvim",
  dependencies = {
    "nvim-telescope/telescope.nvim",
    {
      "3rd/image.nvim",
      opts = { backend = "kitty" },
    },
  },
  config = function()
    require("player").setup({
      panel = {
        elements = {
          artwork = { enabled = true, download = true },
        },
      },
    })
  end,
}
```

### Packer.nvim

```lua
use({
  "mattpetters/nowplaying.nvim",
  requires = {
    "nvim-telescope/telescope.nvim",
    {
      "3rd/image.nvim",
      config = function()
        require("image").setup({ backend = "kitty" })
      end,
    },
  },
  config = function()
    require("player").setup()
  end,
})
```

### Global TUI commands

Install the Go daemon and TUI commands into `${GOBIN:-$(go env GOPATH)/bin}`:

```sh
make go-install
# or
scripts/install.sh
```

This installs `nowplaying` and `nowplayingd`, then links `np` and `nplay` to the TUI command.

```sh
np          # start the daemon if needed, then open the TUI
nplay       # same as np
np --daemon # start only the daemon in the background
np --daemon --debug # start the daemon in the foreground with debug logging
```

Make sure the install directory is on your `PATH`.

## Spotify Authentication 🔐

This fork adds full Spotify Web API support via PKCE OAuth. To use Spotify search, playback control, and queue features:

1. Run `:NowPlayingSpotifyAuth` — this opens a browser for Spotify login.
2. Authorize the app and copy the redirect URL back when prompted.
3. Tokens are persisted locally and refreshed automatically.

To log out: `:NowPlayingSpotifyLogout`

> You can optionally provide your own Spotify `client_id` in the config under `spotify.client_id`.

## Commands ⌨️

| Command | Description |
|---------|-------------|
| `:NowPlayingPlayPause` | Toggle playback |
| `:NowPlayingNext` / `:NowPlayingPrev` | Next / previous track |
| `:NowPlayingStop` | Stop playback |
| `:NowPlayingVolUp` / `:NowPlayingVolDown` | Volume ±5% |
| `:NowPlayingSeekForward` / `:NowPlayingSeekBackward` | Seek ±5s |
| `:NowPlayingTogglePanel` | Open/close the floating panel |
| `:NowPlayingNotify` | Show current track via `vim.notify` |
| `:NowPlayingRefresh` | Refresh player state and redraw UI |
| `:NowPlayingSearch` | Open Telescope Spotify search picker |
| `:NowPlayingSpotifyAuth` | Authenticate with Spotify (PKCE OAuth) |
| `:NowPlayingSpotifyLogout` | Clear Spotify tokens |

### Spotify Authentication

1. Run `:NowPlayingSpotifyAuth` — opens a browser for Spotify login
2. Authorize the app and copy the redirect URL when prompted
3. Tokens are persisted locally and refreshed automatically

To log out: `:NowPlayingSpotifyLogout`

### Configuration

```lua
require("player").setup({
  player_priority = { "apple_music", "spotify", "macos_media" },
  auto_switch = true,
  poll = {
    enabled = true,
    interval_ms = 5000,
  },
  notify = {
    enabled = false,
    timeout = 2500,
    elements = {
      track_title = true, artist = true, album = true,
      status_icon = true, player = true,
    },
  },
  statusline = {
    elements = {
      track_title = true, artist = true, album = true,
      status_icon = true, player = true,
    },
    separator = " - ",
    max_length = 50,
    marquee = {
      enabled = true,
      step_ms = 140,
      pause_ms = 1400,
      gap = "   ",
    },
  },
  keymaps = {
    enabled = true,
    prefix = "<leader>np",
  },
  panel = {
    enabled = true,
    border = { "▛", "▀", "▜", "▐", "▟", "▄", "▙", "▌" },
    draggable = true,
    resizable = true,
    adaptive_colors = true,
    min_width = 30, min_height = 8,
    elements = {
      track_title = true, artist = true, album = true,
      progress_bar = true, volume = true, controls = true,
      artwork = {
        enabled = true,
        cache_dir = vim.fn.stdpath("cache") .. "/nowplaying.nvim",
        download = true,
        width = 20, height = 10,
      },
    },
  },
  spotify = {
    client_id = nil,
    search = { debounce_ms = 300, limit = 7, market = nil },
    actions = { default = "play", secondary = "queue" },
  },
  log_level = "warn",
})
```

### Responsive Panel Breakpoints

| Breakpoint | Min Size | Visible Elements |
|------------|----------|-----------------|
| **Large** | ≥55w × ≥14h | Artwork, title, artist, album, progress bar, controls with key hints |
| **Medium** | ≥40w × ≥10h | Smaller artwork, title, artist, album, progress bar, control icons |
| **Small** | ≥30w × ≥8h | Title, artist, progress bar only |
| **Tiny** | <30w | Title and artist only |

### Statusline

```lua
-- Lualine
local nowplaying = require("player").statusline
require("lualine").setup({
  sections = { lualine_c = { nowplaying } },
})

-- Heirline
local statusline = require("player").statusline
require("heirline").setup({
  statusline = { statusline },
})
```

---

## Development

```bash
# Build both binaries
make go-build

# Run Go tests
make go-test

# Run Neovim tests
make nvim-test

# Run everything
make test-all

# TUI visual iteration loop (requires vhs + ttyd)
make tui-iterate
```

Project structure: `cmd/` (binaries), `internal/` (shared Go packages), `lua/` (Neovim plugin).

---

## Credits

Originally forked from [**Ferouk/nowplaying.nvim**](https://github.com/Ferouk/nowplaying.nvim) by [@Ferouk](https://github.com/Ferouk) — the original author of the AppleScript-based media integration and floating panel concept. Since the fork, the project has grown into a full-featured music player with a shared Go daemon, standalone TUI, real-time audio visualization, and a Neovim client.

Artwork rendering powered by [image.nvim](https://github.com/3rd/image.nvim) by @3rd.

TUI built with [Bubble Tea](https://github.com/charmbracelet/bubbletea) and [Lip Gloss](https://github.com/charmbracelet/lipgloss) by Charm.

## License

GPL-3.0-only. See [LICENSE](./LICENSE).
