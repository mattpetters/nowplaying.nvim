# Standalone TUI + Shared Daemon — Design

**Date:** 2026-04-25
**Branch:** `feat/standalone-tui`
**Status:** Draft, awaiting user review

## Summary

Split nowplaying.nvim into three components so users can install the Neovim
plugin, the standalone TUI, or both, while sharing a single source of truth:

1. **`nowplayingd`** — Go daemon that owns all I/O (provider polling,
   Spotify Web API + PKCE auth, token storage, artwork cache) and serves a
   JSON-RPC protocol over a Unix domain socket.
2. **`nowplaying`** — Go TUI (Bubble Tea + Lip Gloss) that runs in a tmux
   pane, supports keyboard and mouse, and renders artwork via the kitty /
   iterm2 image protocols when the host terminal supports it.
3. **`player.nvim`** (refactor of the existing plugin) — thin Lua client of
   the daemon. Stops doing AppleScript / curl / OAuth itself; subscribes to
   the daemon's event stream and sends commands.

The daemon is the only thing that talks to providers. Both frontends are
"dumb" — they render state and forward user input.

## Goals

- One install path per surface (`brew install nowplaying`, lazy.nvim spec).
- Single Spotify login shared across both frontends.
- Single artwork cache, single state machine, single event clock.
- Mouse + keyboard parity in the TUI.
- Full feature parity with current plugin on day one (state, transport,
  search, playlists, artwork, notifications).
- Tests on every layer, gated in CI.

## Non-Goals

- Linux / Windows support for the macOS providers (Spotify Web API works
  cross-platform, but Apple Music + macOS Media stay macOS-only).
- Plugin-manager integrations beyond lazy.nvim in the docs (others should
  still work — just not exercised).
- Mobile / web frontends (architecture allows them, but out of scope).
- Replacing Telescope as the search picker in Neovim. The plugin keeps
  Telescope; the daemon just provides the search backend.

## Architecture

```
                ┌────────────────────────────┐
                │    nowplayingd (Go)        │
                │  ┌──────────────────────┐  │
   Apple Music ─┼──┤ providers/applemusic │  │
   Spotify ─────┼──┤ providers/spotify    │  │
   macOS Media ─┼──┤ providers/macosmedia │  │
                │  └──────────────────────┘  │
                │  ┌──────────────────────┐  │
                │  │ state machine        │  │
                │  │ artwork cache        │  │
                │  │ token store (PKCE)  │  │
                │  └──────────────────────┘  │
                │  ┌──────────────────────┐  │
                │  │ JSON-RPC over UDS    │  │
                │  └──────────┬───────────┘  │
                └─────────────┼──────────────┘
                              │
            ┌─────────────────┼──────────────────┐
            │                 │                  │
       ┌────▼────┐       ┌────▼─────┐      ┌─────▼─────┐
       │ TUI (Go)│       │ Neovim   │      │ future    │
       │ Bubble  │       │ player.  │      │ clients   │
       │ Tea     │       │ nvim Lua │      │ (Raycast, │
       └─────────┘       └──────────┘      │  menu bar)│
                                           └───────────┘
```

### Components

#### `nowplayingd` (the daemon)

- **Process model.** Single process, one Unix socket at
  `$XDG_RUNTIME_DIR/nowplaying.sock` (fallback `~/.cache/nowplaying/sock`).
- **Lifecycle:** hybrid.
  - Default: auto-spawn by the first client. The Go client library tries
    to connect; on `ENOENT` / `ECONNREFUSED` it forks the daemon binary
    detached, waits up to 2s for the socket, then connects. Daemon
    idle-exits after 5 minutes with no connected clients **and** no
    active playback.
  - Optional always-on: `nowplaying daemon install` writes a launchd
    plist to `~/Library/LaunchAgents/com.nowplaying.daemon.plist`. Users
    who want background notifications opt in.
  - The same daemon binary handles both. `nowplayingd --foreground` for
    debugging, `nowplayingd` for normal use, `nowplaying daemon stop` to
    shut it down cleanly.
- **Provider polling.** A single goroutine per active provider, polling
  at 1Hz when something is playing, 5Hz during a track change, idle when
  no clients connected. The state machine merges provider outputs into a
  single canonical `PlayerState`.
- **Event bus.** Internal pub/sub. Provider goroutines publish raw state;
  state machine deduplicates and re-publishes canonical events
  (`state.changed`, `track.changed`, `progress.tick`, `auth.required`).
- **Spotify auth.** Same PKCE flow the plugin uses today. Tokens stored
  in `~/.local/share/nowplaying/tokens.json` (mode 0600). Auth flow is
  driven by the *client* (TUI shows a code, Neovim shows a notification);
  the daemon just hosts the localhost callback server during the flow.
- **Artwork cache.** SHA-256 of the artwork URL → file in
  `~/.cache/nowplaying/artwork/`. ImageMagick is no longer required;
  daemon downloads with `net/http` and serves the local path to clients.
  Clients decide how to render (kitty/iterm2 protocol in TUI, image.nvim
  in Neovim).
- **Logging.** stderr + structured (slog), file rotation handled by
  launchd or the user. `nowplaying daemon logs` tails the file when
  running detached.

#### Protocol — JSON-RPC 2.0 over Unix socket

Methods (versioned under `nowplaying/v1/`):

| Method | Direction | Purpose |
|---|---|---|
| `state.get` | client → daemon | Fetch current canonical state |
| `state.subscribe` | client → daemon | Stream state events |
| `transport.play` / `pause` / `toggle` | c→d | Transport control |
| `transport.next` / `prev` | c→d | Skip controls |
| `transport.seek` | c→d | `{ms: int}` |
| `transport.volume` | c→d | `{level: 0..100}` |
| `provider.list` | c→d | Available providers + active flag |
| `provider.set` | c→d | Force-select active provider |
| `search.query` | c→d | `{q, type, limit}` → tracks/albums/playlists |
| `search.play` | c→d | Play a result (uri, context) |
| `playlist.list` / `playlist.tracks` | c→d | Browse playlists |
| `auth.start` | c→d | Begin Spotify PKCE flow; returns auth URL |
| `auth.status` | c→d | Connected? token valid? expiring? |

Notifications (daemon → client, server-initiated):

| Notification | Payload |
|---|---|
| `state.changed` | full `PlayerState` |
| `track.changed` | `{prev, current}` |
| `progress.tick` | `{position_ms, duration_ms, ts}` (1Hz when playing) |
| `auth.required` | `{provider}` |
| `error` | `{provider, code, message}` |

Schema lives in `proto/v1.go` as Go structs with JSON tags, generated
into a JSON Schema file (`proto/v1.schema.json`) for the Lua client to
validate against.

#### `nowplaying` (the TUI)

- **Framework.** Bubble Tea (model-update-view) + Lip Gloss (styling) +
  Bubbles (text input, list, viewport components).
- **Modes.** Single screen with three panes that resize responsively:
  - Now-playing (artwork, metadata, progress bar).
  - Search / browse (collapsible; spawns on `/`).
  - Help / status (key hints, daemon connection state).
- **Input.** Both keyboard and mouse, registered through Bubble Tea's
  `tea.WithMouseAllMotion`. Default keymap mirrors the Neovim plugin:
  - `space` toggle play, `n`/`p` next/prev, `[`/`]` seek -10/+10s,
    `+`/`-` volume, `/` search, `tab` cycle provider, `q` quit.
  - Mouse: click progress bar to seek; click track row to play; scroll
    to navigate lists; right-click for context menu (planned, not v1).
- **Artwork rendering.** Detect terminal via `TERM` and
  `KITTY_WINDOW_ID` / `TERM_PROGRAM`. Use kitty graphics protocol or
  iterm2 inline images when available; fall back to ASCII-art (using
  `qeesung/image2ascii`) otherwise. Artwork only re-renders on track
  change to avoid flicker.
- **Resilience.** If the daemon disconnects, the TUI shows a
  reconnecting banner and retries with exponential backoff. State is
  cached in-memory so the screen doesn't go blank.

#### `player.nvim` (refactored Lua plugin)

- **What stays.** Panel UI (drag, resize, marquee statusline,
  notifications), Telescope picker, image.nvim integration, all the
  keymaps and commands.
- **What changes.** All provider files become daemon clients. The
  `lua/player/providers/` and `lua/player/spotify_api/` directories
  collapse into one `lua/player/daemon/client.lua` that speaks JSON-RPC
  over the Unix socket via `vim.uv.new_pipe()`. Auth, polling, and
  AppleScript invocations are deleted.
- **Backwards compat.** First-run detects no daemon installed → prompts
  user with install instructions (`brew install nowplaying` or a curl
  one-liner) and a fallback "legacy mode" that uses the old in-process
  Lua providers. Legacy mode is removed in a follow-up release.

## Data Flow Examples

**Pressing space in the TUI:**
1. TUI sends `transport.toggle`.
2. Daemon picks the active provider, runs `osascript ... pause` (or
   Spotify Web API `PUT /me/player/pause`).
3. Provider goroutine sees the new state on its next poll.
4. State machine emits `state.changed`.
5. All connected clients receive the notification and re-render.

**New Spotify track starts (no client interaction):**
1. Spotify provider polls, sees a new `item.id`.
2. State machine produces `track.changed` + `state.changed`.
3. Daemon downloads artwork to cache (if not already cached).
4. Notifications fire to all subscribed clients.
5. TUI re-renders artwork; Neovim plugin shows `vim.notify` toast and
   re-renders panel.

**Spotify token expired:**
1. Provider's HTTP call returns 401.
2. State machine emits `auth.required`.
3. TUI shows a banner: "Spotify auth expired — press A to reconnect."
   Neovim plugin shows a `vim.notify` with the same hint.
4. User presses `A` → client calls `auth.start` → daemon spins up the
   localhost callback server and returns the auth URL → client opens it
   in the user's browser.

## Error Handling

- **Provider errors.** Bubbled as `error` notifications. State machine
  marks the provider as degraded but doesn't crash. Client decides
  whether to surface — TUI flashes a transient toast at the bottom.
- **Socket disconnects.** Both clients reconnect with exponential
  backoff (100ms → 5s, capped). State is preserved across reconnects.
- **Daemon crash.** Auto-spawn re-launches it on next client request.
  systemd-style restart loops are out of scope; if the daemon panics
  three times in a minute it logs and exits, surfacing through the
  client.
- **Concurrent transport commands.** The daemon serializes per-provider
  commands with a mutex. The state machine throws away stale provider
  state if a command was issued in the last 250ms (avoids the "I just
  hit pause but the next poll says playing" bounce).

## Testing Strategy

Test pyramid, every layer:

### Daemon (Go)

- **Unit tests** (`go test ./...`):
  - `proto/`: encode/decode round-trips for every method and notification,
    schema validation, error frames.
  - `state/`: state machine reducer tests — given (event, prior state)
    produce expected (new state, emitted notifications).
  - `providers/spotify`: HTTP client tests using `httptest` server
    fixtures; PKCE flow tested against a fake auth server.
  - `providers/applemusic`, `macosmedia`: shell-out functions get a
    `runner` interface; tests inject a fake runner with golden output
    files (`testdata/applemusic/playing.txt` etc.).
  - `cache/`: artwork cache hit/miss/expiry/concurrency.
- **Integration tests** (`go test -tags=integration`):
  - Spin up daemon in-process on a temp socket, drive the JSON-RPC
    protocol with a real client connection, verify state changes
    propagate.
  - Multi-client tests: two simulated clients receive the same events
    in order.
- **End-to-end** (`go test -tags=e2e`, opt-in, macOS-only):
  - Drive Apple Music with `osascript`, assert state via daemon,
    transition through play / pause / next, verify notifications.
  - Skipped in CI; run locally with `make test-e2e`.
- **Coverage gate.** CI fails below 75% on `internal/state` and
  `internal/proto`. Provider packages exempted (mostly shell-outs).

### TUI (Go)

- **Snapshot tests** with Bubble Tea's `teatest`:
  - Drive synthetic key/mouse events into the model, assert rendered
    output matches `testdata/snapshots/*.golden`.
  - Cover: initial render, play/pause toggle, search open, search
    results render, auth-required banner, disconnected banner, mouse
    click on progress bar.
- **Update tests.** Pure `Update(msg) -> (model, cmd)` reducers tested
  without rendering for fast feedback.
- **Manual smoke checklist** in `docs/tui-smoke-test.md`. Run before
  release.

### Neovim plugin (Lua, busted)

- Existing busted setup is reused. New tests live in
  `tests/player/daemon/` and cover:
  - JSON-RPC encode/decode.
  - Reconnect logic with a fake socket server (lua-socket or a
    spawned `socat` listener in the test harness).
  - Plugin behavior with daemon present, daemon absent, daemon
    crashing mid-session.
- Old provider tests are deleted along with the providers.

### CI

- GitHub Actions matrix:
  - `make lint` (golangci-lint, stylua, luacheck).
  - `make test` (Go unit + integration, Lua busted).
  - `make build` (cross-compile daemon + TUI for darwin/amd64 +
    darwin/arm64).
- E2E job is a separate workflow, manual-trigger only, runs on a
  self-hosted macOS runner if/when one is set up.

## Repo Layout

The repo becomes a multi-component monorepo:

```
nowplaying.nvim/                 # repo root keeps this name for now
├── cmd/
│   ├── nowplayingd/             # daemon entry point
│   └── nowplaying/              # TUI entry point
├── internal/
│   ├── proto/                   # JSON-RPC types + schema
│   ├── state/                   # canonical state machine
│   ├── providers/
│   │   ├── applemusic/
│   │   ├── spotify/
│   │   └── macosmedia/
│   ├── cache/                   # artwork cache
│   ├── auth/                    # PKCE token store
│   └── ipc/                     # socket server + client
├── tui/                         # Bubble Tea models + components
├── lua/player/                  # Neovim plugin (refactored)
│   ├── daemon/
│   │   └── client.lua           # NEW: thin RPC client
│   ├── ui/                      # unchanged panel/statusline/notify
│   ├── telescope/               # unchanged search picker UI
│   └── ...                      # init/config/state thinned out
├── plugin/                      # Neovim entry — unchanged
├── tests/                       # Lua busted tests
├── go.mod
├── Makefile                     # `test`, `test-e2e`, `build`, `install`
├── .github/workflows/
└── docs/
    ├── superpowers/specs/       # this file
    ├── protocol.md              # NEW: protocol reference
    └── tui-smoke-test.md        # NEW: manual checklist
```

## Distribution

- **Daemon + TUI:** Homebrew tap (`brew install mpetters/tap/nowplaying`).
  Tap repo built later. Until then, users can `go install` from this
  repo or grab a release binary from GitHub Releases (goreleaser).
- **Neovim plugin:** unchanged install path. The plugin's README points
  at the brew install for the daemon.

## Migration Plan (within this branch)

Phased so each phase compiles, tests pass, and the plugin still works:

1. **Phase 1 — Daemon skeleton.** `cmd/nowplayingd`, `internal/ipc`,
   `internal/proto`, `internal/state`. Stub providers that return fake
   data. End-to-end test: client connects, calls `state.get`, gets
   stub state.
2. **Phase 2 — Real providers.** Port Apple Music, macOS Media, Spotify
   read paths. Tests against golden fixtures.
3. **Phase 3 — Transport + auth.** Port play/pause/next/prev/seek/volume
   for all providers. Spotify PKCE flow.
4. **Phase 4 — Search + playlists.** Port Spotify search + playlist
   browsing.
5. **Phase 5 — Artwork cache.** Replace ImageMagick with native Go
   download + serve local path.
6. **Phase 6 — TUI.** Bubble Tea app, all panes, mouse + keyboard.
   teatest snapshots.
7. **Phase 7 — Refactor Neovim plugin.** Delete in-process providers,
   add `lua/player/daemon/client.lua`, wire the panel + Telescope to
   the daemon. Legacy fallback for users without daemon installed.
8. **Phase 8 — Distribution.** Goreleaser config, brew formula in a
   tap, CI workflows, install / uninstall scripts. README updates.

Each phase is its own commit (or small commit series) on
`feat/standalone-tui`. PR opens after Phase 7 lands so the branch is
shippable; Phase 8 can land as a follow-up if needed.

## Open Questions

None blocking. Tradeoffs called out inline.

## Risks

- **macOS provider drift.** AppleScript output formats can change between
  macOS versions. Mitigation: golden fixtures plus an opt-in e2e suite
  the user can run on each macOS upgrade.
- **Bubble Tea + image rendering.** Kitty / iterm2 image protocols
  inside Bubble Tea have known edge cases (the rendered image must not
  be redrawn on every frame, only on state change). Mitigation: gate
  artwork redraw on `track.changed`.
- **Daemon auto-spawn race.** If two clients launch at once, both may
  try to fork. Mitigation: use a lock file (`flock` on
  `~/.cache/nowplaying/spawn.lock`) during spawn.
- **Backwards compatibility.** Existing plugin users on `main` updating
  to this branch will break until they install the daemon. Mitigation:
  the legacy fallback in Phase 7 keeps things working until the user
  installs the daemon, with a deprecation banner.
