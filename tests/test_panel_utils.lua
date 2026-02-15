-- Unit tests for panel_utils (pure helper functions)
-- These run in the child Neovim process since they depend on vim.fn.
local H = dofile("tests/helpers.lua")

local T = MiniTest.new_set({
  hooks = {
    pre_once = function()
      _G.child = H.new_child()
      H.setup_plugin(child)
    end,
    post_once = function()
      child.stop()
    end,
  },
})

-- ── truncate_text ──────────────────────────────────────────────

T["truncate_text"] = MiniTest.new_set()

T["truncate_text"]["returns empty string for nil input"] = function()
  local result = child.lua_get([[require("player.ui.panel_utils").truncate_text(nil, 20)]])
  MiniTest.expect.equality(result, "")
end

T["truncate_text"]["returns original when within width"] = function()
  local result = child.lua_get([[require("player.ui.panel_utils").truncate_text("hello", 20)]])
  MiniTest.expect.equality(result, "hello")
end

T["truncate_text"]["truncates with ellipsis when too long"] = function()
  local result = child.lua_get([[require("player.ui.panel_utils").truncate_text("abcdefghij", 8)]])
  -- 8 chars: 5 visible + "..." = 8
  MiniTest.expect.equality(result, "abcde...")
end

T["truncate_text"]["handles max_width <= 3 as dots"] = function()
  local result = child.lua_get([[require("player.ui.panel_utils").truncate_text("abcdefgh", 3)]])
  MiniTest.expect.equality(result, "...")
end

T["truncate_text"]["exact fit returns unchanged"] = function()
  local result = child.lua_get([[require("player.ui.panel_utils").truncate_text("abcde", 5)]])
  MiniTest.expect.equality(result, "abcde")
end

-- ── center_text ────────────────────────────────────────────────

T["center_text"] = MiniTest.new_set()

T["center_text"]["pads short text symmetrically"] = function()
  local result = child.lua_get([[require("player.ui.panel_utils").center_text("hi", 6)]])
  -- 6 - 2 = 4 padding; left=2, right=2
  MiniTest.expect.equality(result, "  hi  ")
end

T["center_text"]["returns text unchanged when wider than width"] = function()
  local result = child.lua_get([[require("player.ui.panel_utils").center_text("long text", 4)]])
  MiniTest.expect.equality(result, "long text")
end

T["center_text"]["handles odd padding (extra space on right)"] = function()
  local result = child.lua_get([[require("player.ui.panel_utils").center_text("ab", 5)]])
  -- 5 - 2 = 3; left=1, right=2
  MiniTest.expect.equality(result, " ab  ")
end

-- ── format_time ────────────────────────────────────────────────

T["format_time"] = MiniTest.new_set()

T["format_time"]["formats seconds correctly"] = function()
  local result = child.lua_get([[require("player.ui.panel_utils").format_time(65)]])
  MiniTest.expect.equality(result, "1:05")
end

T["format_time"]["returns ?:?? for nil"] = function()
  local result = child.lua_get([[require("player.ui.panel_utils").format_time(nil)]])
  MiniTest.expect.equality(result, "?:??")
end

T["format_time"]["handles zero"] = function()
  local result = child.lua_get([[require("player.ui.panel_utils").format_time(0)]])
  MiniTest.expect.equality(result, "0:00")
end

T["format_time"]["handles large values"] = function()
  local result = child.lua_get([[require("player.ui.panel_utils").format_time(3661)]])
  MiniTest.expect.equality(result, "61:01")
end

-- ── progress_bar ───────────────────────────────────────────────

T["progress_bar"] = MiniTest.new_set()

T["progress_bar"]["empty when no position/duration"] = function()
  local result = child.lua_get([[require("player.ui.panel_utils").progress_bar(nil, nil, 10)]])
  MiniTest.expect.equality(result, "░░░░░░░░░░")
end

T["progress_bar"]["full bar at 100%"] = function()
  local result = child.lua_get([[require("player.ui.panel_utils").progress_bar(100, 100, 10)]])
  MiniTest.expect.equality(result, "██████████")
end

T["progress_bar"]["half bar at 50%"] = function()
  local result = child.lua_get([[require("player.ui.panel_utils").progress_bar(50, 100, 10)]])
  MiniTest.expect.equality(result, "█████░░░░░")
end

T["progress_bar"]["clamps ratio to 0..1"] = function()
  local result = child.lua_get([[require("player.ui.panel_utils").progress_bar(200, 100, 10)]])
  MiniTest.expect.equality(result, "██████████")
end

T["progress_bar"]["empty bar when duration is 0"] = function()
  local result = child.lua_get([[require("player.ui.panel_utils").progress_bar(50, 0, 10)]])
  MiniTest.expect.equality(result, "░░░░░░░░░░")
end

-- ── detect_zone ────────────────────────────────────────────────
-- detect_zone(rel_row, rel_col, total_width, total_height, grab_size)
-- rel_row / rel_col are 0-indexed from window top-left (including border).
-- total_width / total_height include the border (content + 2 for rounded).
-- grab_size = number of cells from each edge that count as resize zone.
-- Returns: "body", "top", "bottom", "left", "right",
--          "top_left", "top_right", "bottom_left", "bottom_right"

T["detect_zone"] = MiniTest.new_set()

T["detect_zone"]["center of window is body"] = function()
  -- 60x20 window, grab=2, click at center (30, 10)
  local z = child.lua_get([[require("player.ui.panel_utils").detect_zone(10, 30, 60, 20, 2)]])
  MiniTest.expect.equality(z, "body")
end

T["detect_zone"]["top-left corner"] = function()
  -- (0,0) = top-left corner
  local z = child.lua_get([[require("player.ui.panel_utils").detect_zone(0, 0, 60, 20, 2)]])
  MiniTest.expect.equality(z, "top_left")
end

T["detect_zone"]["top-right corner"] = function()
  -- (0, 59) = top-right corner (0-indexed, total_width=60 -> last col=59)
  local z = child.lua_get([[require("player.ui.panel_utils").detect_zone(0, 59, 60, 20, 2)]])
  MiniTest.expect.equality(z, "top_right")
end

T["detect_zone"]["bottom-left corner"] = function()
  local z = child.lua_get([[require("player.ui.panel_utils").detect_zone(19, 0, 60, 20, 2)]])
  MiniTest.expect.equality(z, "bottom_left")
end

T["detect_zone"]["bottom-right corner"] = function()
  local z = child.lua_get([[require("player.ui.panel_utils").detect_zone(19, 59, 60, 20, 2)]])
  MiniTest.expect.equality(z, "bottom_right")
end

T["detect_zone"]["top edge (not corner)"] = function()
  -- row=0, col=30 (middle of top edge)
  local z = child.lua_get([[require("player.ui.panel_utils").detect_zone(0, 30, 60, 20, 2)]])
  MiniTest.expect.equality(z, "top")
end

T["detect_zone"]["bottom edge (not corner)"] = function()
  local z = child.lua_get([[require("player.ui.panel_utils").detect_zone(19, 30, 60, 20, 2)]])
  MiniTest.expect.equality(z, "bottom")
end

T["detect_zone"]["left edge (not corner)"] = function()
  local z = child.lua_get([[require("player.ui.panel_utils").detect_zone(10, 0, 60, 20, 2)]])
  MiniTest.expect.equality(z, "left")
end

T["detect_zone"]["right edge (not corner)"] = function()
  local z = child.lua_get([[require("player.ui.panel_utils").detect_zone(10, 59, 60, 20, 2)]])
  MiniTest.expect.equality(z, "right")
end

T["detect_zone"]["grab_size=1 inside boundary is body"] = function()
  -- With grab_size=2: row=2, col=2 should be body (just past the grab zone)
  local z = child.lua_get([[require("player.ui.panel_utils").detect_zone(2, 2, 60, 20, 2)]])
  MiniTest.expect.equality(z, "body")
end

T["detect_zone"]["corner extends grab_size cells in each direction"] = function()
  -- grab_size=2: (1, 1) is still top_left corner
  local z = child.lua_get([[require("player.ui.panel_utils").detect_zone(1, 1, 60, 20, 2)]])
  MiniTest.expect.equality(z, "top_left")
end

-- ── clamp_size ─────────────────────────────────────────────────
-- clamp_size(width, height, min_w, min_h, max_w, max_h)
-- Returns clamped {width, height}.

T["clamp_size"] = MiniTest.new_set()

T["clamp_size"]["returns same size when within bounds"] = function()
  local r = child.lua_get([[require("player.ui.panel_utils").clamp_size(40, 15, 30, 8, 100, 50)]])
  MiniTest.expect.equality(r, { 40, 15 })
end

T["clamp_size"]["clamps below minimum"] = function()
  local r = child.lua_get([[require("player.ui.panel_utils").clamp_size(10, 3, 30, 8, 100, 50)]])
  MiniTest.expect.equality(r, { 30, 8 })
end

T["clamp_size"]["clamps above maximum"] = function()
  local r = child.lua_get([[require("player.ui.panel_utils").clamp_size(200, 80, 30, 8, 100, 50)]])
  MiniTest.expect.equality(r, { 100, 50 })
end

T["clamp_size"]["clamps width and height independently"] = function()
  local r = child.lua_get([[require("player.ui.panel_utils").clamp_size(10, 80, 30, 8, 100, 50)]])
  MiniTest.expect.equality(r, { 30, 50 })
end

-- ── detect_zone edge-grab UX problem (documenting) ────────────
-- With grab_size=2, a 62x22 total window (60+border) has only a
-- 2-cell rim for resize.  Everything else (56x18 interior) returns
-- "body".  This documents why edge-grab is nearly unusable.

T["detect_zone"]["interior point 3 cells from edge is body with grab_size=2"] = function()
  -- (2, 2) is just outside the 2-cell grab zone → body
  local z = child.lua_get([[require("player.ui.panel_utils").detect_zone(2, 2, 62, 22, 2)]])
  MiniTest.expect.equality(z, "body")
end

T["detect_zone"]["interior point at 25% in is body with grab_size=2"] = function()
  -- (5, 15) well inside a 62x22 window → body
  local z = child.lua_get([[require("player.ui.panel_utils").detect_zone(5, 15, 62, 22, 2)]])
  MiniTest.expect.equality(z, "body")
end

-- ── nearest_corner ─────────────────────────────────────────────
-- nearest_corner(rel_row, rel_col, total_width, total_height)
-- Maps any position to the closest corner of the window.
-- Used by right-drag resize so the entire window is a resize target.

T["nearest_corner"] = MiniTest.new_set()

T["nearest_corner"]["top-left quadrant"] = function()
  -- (3, 5) in a 60x20 window → top-left
  local c = child.lua_get([[require("player.ui.panel_utils").nearest_corner(3, 5, 60, 20)]])
  MiniTest.expect.equality(c, "top_left")
end

T["nearest_corner"]["top-right quadrant"] = function()
  -- (3, 55) in a 60x20 window → top-right
  local c = child.lua_get([[require("player.ui.panel_utils").nearest_corner(3, 55, 60, 20)]])
  MiniTest.expect.equality(c, "top_right")
end

T["nearest_corner"]["bottom-left quadrant"] = function()
  -- (17, 5) in a 60x20 window → bottom-left
  local c = child.lua_get([[require("player.ui.panel_utils").nearest_corner(17, 5, 60, 20)]])
  MiniTest.expect.equality(c, "bottom_left")
end

T["nearest_corner"]["bottom-right quadrant"] = function()
  -- (17, 55) in a 60x20 window → bottom-right
  local c = child.lua_get([[require("player.ui.panel_utils").nearest_corner(17, 55, 60, 20)]])
  MiniTest.expect.equality(c, "bottom_right")
end

T["nearest_corner"]["exact center rounds to bottom-right"] = function()
  -- (10, 30) is exact center of 60x20; half-row=10, half-col=30
  -- With >= comparisons, center falls into bottom-right
  local c = child.lua_get([[require("player.ui.panel_utils").nearest_corner(10, 30, 60, 20)]])
  MiniTest.expect.equality(c, "bottom_right")
end

T["nearest_corner"]["origin is top-left"] = function()
  local c = child.lua_get([[require("player.ui.panel_utils").nearest_corner(0, 0, 60, 20)]])
  MiniTest.expect.equality(c, "top_left")
end

T["nearest_corner"]["last cell is bottom-right"] = function()
  local c = child.lua_get([[require("player.ui.panel_utils").nearest_corner(19, 59, 60, 20)]])
  MiniTest.expect.equality(c, "bottom_right")
end

T["nearest_corner"]["top edge center maps to top-right"] = function()
  -- (0, 30) → top half, right half
  local c = child.lua_get([[require("player.ui.panel_utils").nearest_corner(0, 30, 60, 20)]])
  MiniTest.expect.equality(c, "top_right")
end

T["nearest_corner"]["left edge center maps to bottom-left"] = function()
  -- (10, 0) → bottom half, left half
  local c = child.lua_get([[require("player.ui.panel_utils").nearest_corner(10, 0, 60, 20)]])
  MiniTest.expect.equality(c, "bottom_left")
end

return T
