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

return T
