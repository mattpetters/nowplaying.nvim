# nowplaying.nvim — Roadmap

> Last updated: 2026-02-21

## Overview

This roadmap tracks UX improvements, bug fixes, and test coverage goals for the nowplaying.nvim plugin, focusing on three key areas: Telescope integration, Spotify playlist support, and the floating panel mini-player.

---

## 1. Telescope Album Art in List Entries

**Status:** 🟡 Deferred (preview-only art works; inline list thumbnails impractical)  
**Priority:** Medium

### Problem
Album art only renders in the Telescope **preview pane** (via image.nvim). The results **list entries** show only text columns (icon | type | main text) with no album art thumbnails.

### Investigation Findings
- Telescope's `entry_display` doesn't natively support images
- image.nvim renders at absolute window coordinates; the scrolling results list makes per-row thumbnails very difficult (coordinates shift on scroll, entries get recycled)
- Kitty/iTerm2 inline image protocols have similar scroll-sync issues inside Neovim buffers

### Current State
- Album art renders correctly in the **preview pane** — this already works well
- List entries use styled Nerd Font icons per result type (track, album, artist, playlist)

### Remaining Options
- [ ] Enhance list entries with richer styled Nerd Font icons / colored highlights
- [ ] Explore `image.nvim` overlay approach if the library adds scroll-aware rendering
- [ ] Accept preview-only art as the stable v1 solution

---

## 2. Playlist Support (Release Radar, Dynamic Playlists)

**Status:** ✅ Complete  
**Priority:** High

### What Was Done
- [x] **Play in context**: Tracks from playlist/album drill-downs now play with `context_uri` + `offset_uri` so Spotify continues through the playlist
- [x] **Play entire playlist**: `<CR>` on a playlist entry plays the whole playlist from the beginning
- [x] **Playlist-specific actions**: `<CR>` = play entire playlist, `<C-t>` = browse/drill-down into tracks
- [x] **Album context**: Album drill-down tracks also play in album context with `album_uri` propagated
- [x] `playlist_uri` propagated to tracks during playlist drill-down
- [x] `album_uri` propagated to tracks during album drill-down
- [x] Updated preview hints and results title to reflect new mappings

### Remaining (nice-to-have)
- [ ] Verify "Release Radar", "Discover Weekly", "Daily Mix" playlists with live testing
- [ ] Handle edge cases: empty playlists, playlists with local files, podcast episodes mixed in

---

## 3. Floating Panel Mini-Player UX

**Status:** ✅ Core Complete  
**Priority:** High

### What Was Done

#### Responsive Layout (auto-hide at breakpoints)
- [x] Defined width/height breakpoints for progressive element hiding
- [x] **Large** (≥60w, ≥14h): Full layout — artwork, title, artist, album, progress bar, controls with keyhints
- [x] **Medium** (≥45w, ≥10h): Hide album text, shrink artwork, hide key hints (keep control icons)
- [x] **Small** (≥30w, ≥8h): Hide artwork entirely, hide controls, show only title + artist + progress
- [x] **Tiny** (<30w): Show only title + artist
- [x] Breakpoint logic extracted to `panel_utils.lua` as pure functions
- [x] Panel re-evaluates layout on resize

#### Layout Functions (panel_utils.lua)
- [x] `layout_breakpoint(width, height)` — returns "large"/"medium"/"small"/"tiny"
- [x] `visible_elements(width, height)` — returns table of booleans for which elements to show
- [x] `compute_artwork_size(panel_width, panel_height, breakpoint)` — responsive artwork dimensions
- [x] `compute_layout(width, height)` — master layout computation combining all the above

#### Artwork Improvements
- [x] Artwork scales proportionally to panel size instead of fixed width/height
- [x] Don't reserve artwork space when panel is too small to show it

#### Controls UX
- [x] Hide `[key]` hint labels at medium sizes (keep icons only)
- [x] Hide entire controls row at small sizes

#### Panel Rendering
- [x] `render()` refactored to use `panel_utils.compute_layout()`
- [x] `compute_content_height()` refactored to use responsive layout
- [x] `force_redraw()` fixed to use `state.current` directly (avoids state reset bug)

#### Tests (71+ new tests)
- [x] Responsive breakpoint logic — 28+ tests in `test_panel_utils.lua`
- [x] Element visibility at different panel sizes
- [x] Artwork scaling calculations
- [x] Layout computation master function
- [x] Panel force_redraw functional test
- [x] Panel resize behavior functional tests
- [x] Panel responsive layout functional tests

### Remaining (future polish)
- [ ] Smooth transitions when artwork changes (fade or immediate swap, no flicker)
- [ ] Volume indicator (visual bar, not just +/- keys)
- [ ] Seek bar interactive (click to seek)
- [ ] Debounce render calls during rapid state updates
- [ ] Skip full re-render when only position changed (update progress bar line only)
- [ ] Batch vim API calls where possible

---

## 4. Test Coverage Goals

**Status:** ✅ Strong (340 tests passing, 0 failures)

### Current Coverage
| Module | Tests | Status |
|--------|-------|--------|
| `panel_utils.lua` | `test_panel_utils.lua` (71 tests) | ✅ Comprehensive — breakpoints, visibility, artwork scaling, layout |
| `panel.lua` | `test_panel.lua` (37 tests) | ✅ Lifecycle, keys, rendering, responsive layout, resize |
| `search.lua` helpers | `test_search.lua` (28 tests) | ✅ Formatting functions |
| `colors.lua` | `test_colors.lua` (37 tests) | ✅ Color math, desaturate |
| `artwork.lua` | `test_artwork.lua` (14 tests) | ✅ Cache logic |
| `client.lua` | `test_client.lua` (15 tests) | ✅ API parsing |
| `auth.lua` | `test_auth.lua` (19 tests) | ✅ OAuth flow |
| `token_store.lua` | `test_token_store.lua` (19 tests) | ✅ Token persistence |
| `state.lua` | `test_state.lua` (13 tests) | ✅ State machine |
| `statusline.lua` | `test_statusline.lua` (11 tests) | ✅ Statusline formatting |
| `config.lua` | `test_config.lua` (8 tests) | ✅ Config defaults/merge |
| `utils.lua` | `test_utils.lua` (28 tests) | ✅ Utility functions |
| `log.lua` | `test_log.lua` (11 tests) | ✅ Logging |
| `macos_media.lua` | `test_macos_media.lua` (21 tests) | ✅ macOS media provider |
| `notify.lua` | `test_notify.lua` (8 tests) | ✅ Notifications |

### Future Test Additions
- [ ] Playlist context playback integration test (requires Spotify API mock or live)
- [ ] Telescope picker functional tests (requires Telescope test harness)

---

## Implementation Order

1. ~~**Tests first**: Write failing tests for responsive layout breakpoints and element visibility~~ ✅
2. ~~**Extract layout logic**: Move breakpoint calculations to `panel_utils.lua`~~ ✅
3. ~~**Implement responsive panel**: Add breakpoint-driven element hiding~~ ✅
4. ~~**Fix playlist context**: Wire up `context_uri` + `offset` for playlist playback~~ ✅
5. **Telescope album art**: Deferred — preview pane art works; inline list art impractical with current image.nvim
6. **Polish**: Debounced renders, artwork transitions, interactive seek bar (future)

---

## Changelog

### 2026-02-21
- Initial roadmap created
- Audited existing codebase and test coverage
- Identified three priority areas: telescope art, playlists, panel UX
- Implemented responsive layout system in `panel_utils.lua` (4 pure functions, 71+ tests)
- Refactored `panel.lua` render/compute_content_height to use responsive layout
- Fixed `force_redraw()` state reset bug
- Fixed playlist context playback in `search.lua` (`context_uri` + `offset_uri`)
- Added `<CR>` = play playlist, `<C-t>` = browse tracks mappings
- Added album context playback (tracks play within album)
- Added 8 panel functional tests (responsive layout, force_redraw, resize)
- All 340 tests passing, 0 failures
- Deferred Telescope inline list art (impractical with image.nvim scroll constraints)
