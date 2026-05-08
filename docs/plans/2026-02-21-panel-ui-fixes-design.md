# Panel UI Fixes Design

**Date:** 2026-02-21
**Status:** Approved

## Problems

1. **Background too dark** — `apply_accent` uses `darken(accent, 0.80)` + `desaturate(0.90)`, producing near-black with no accent character
2. **No stacked layout** — when panel is resized to square-ish aspect ratio, artwork stays side-by-side and gets cramped
3. **Artwork doesn't adapt** — artwork size is fixed per breakpoint, doesn't scale with panel dimensions in portrait mode

## Approach: Blend-based background + stacked layout mode

### 1. Background Tint (`colors.lua`)

New `blend_with_bg(accent_hex, opacity, bg_hex)` function:
- Linearly interpolates each RGB channel: `result = bg * (1 - opacity) + accent * opacity`
- `bg_hex` parameter optional — falls back to editor's `Normal` bg highlight
- `apply_accent` calls `blend_with_bg(accent, 0.3)` instead of darken/desaturate chain
- Border uses `blend_with_bg(accent, 0.6)` for a stronger but still muted frame

### 2. Stacked Layout (`panel_utils.lua`)

Add `orientation` field to `compute_layout`:
- `"landscape"` (default): side-by-side artwork + metadata (current behavior)
- `"portrait"`: artwork centered above, metadata centered below
- Threshold: `width < 1.5 * height` triggers portrait mode
- In portrait: artwork sized to fill width (capped at `min(width - 4, height * 0.5)`)
- Metadata renders below artwork, centered

### 3. Panel Render (`panel.lua`)

Branch on `layout.orientation`:
- `"portrait"`: blank rows for artwork overlay, then centered metadata below
- `"landscape"`: current side-by-side code path
- `try_render_image` adapts dimensions based on orientation

### 4. Test Coverage

- `blend_with_bg` — basic blending, edge cases (0/1 opacity, invalid input)
- `get_editor_bg` — fallback behavior
- `compute_layout` orientation — landscape vs portrait at various aspect ratios
- `compute_artwork_size` — portrait mode sizing
- Panel render — stacked layout output verification
