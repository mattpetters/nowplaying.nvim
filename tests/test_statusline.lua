-- Unit tests for lua/player/ui/statusline.lua
-- Tests statusline output formatting, truncation, and marquee logic.
local H = dofile("tests/helpers.lua")

local T = MiniTest.new_set({
  hooks = {
    pre_once = function()
      _G.child = H.new_child()
      H.setup_plugin(child, {})
    end,
    post_once = function()
      child.stop()
    end,
    pre_case = function()
      child.lua([[
        package.loaded["player.state"] = nil
        package.loaded["player.ui.statusline"] = nil
        require("player.config").setup({})
        _G.state = require("player.state")
        _G.statusline = require("player.ui.statusline")
      ]])
    end,
  },
})

-- ── inactive state ─────────────────────────────────────────────

T["inactive"] = MiniTest.new_set()

T["inactive"]["shows inactive message when no player"] = function()
  child.lua([[state.current = { status = "inactive" }]])
  local r = child.lua_get([[statusline.statusline()]])
  MiniTest.expect.equality(r, "NowPlaying: inactive")
end

-- ── playing state ──────────────────────────────────────────────

T["playing"] = MiniTest.new_set()

T["playing"]["includes track title"] = function()
  H.set_state(child, H.make_state({ status = "playing" }))
  local r = child.lua_get([[statusline.statusline()]])
  MiniTest.expect.equality(r:find("Test Track") ~= nil, true)
end

T["playing"]["includes artist name"] = function()
  H.set_state(child, H.make_state({ status = "playing" }))
  local r = child.lua_get([[statusline.statusline()]])
  MiniTest.expect.equality(r:find("Test Artist") ~= nil, true)
end

T["playing"]["includes play icon for playing status"] = function()
  H.set_state(child, H.make_state({ status = "playing" }))
  local r = child.lua_get([[statusline.statusline()]])
  MiniTest.expect.equality(r:find("▶") ~= nil, true)
end

T["playing"]["includes pause icon for paused status"] = function()
  H.set_state(child, H.make_state({ status = "paused" }))
  local r = child.lua_get([[statusline.statusline()]])
  MiniTest.expect.equality(r:find("⏸") ~= nil, true)
end

-- ── truncation ─────────────────────────────────────────────────

T["truncation"] = MiniTest.new_set()

T["truncation"]["respects max_length"] = function()
  child.lua([[
    require("player.config").setup({
      statusline = { max_length = 30 }
    })
  ]])
  H.set_state(child, H.make_state({
    status = "playing",
    track = {
      title = "A Very Long Track Title That Should Be Truncated",
      artist = "A Very Long Artist Name",
      album = "A Very Long Album Name",
      duration = 240,
    },
  }))
  local r = child.lua_get([[statusline.statusline()]])
  local width = child.lua_get(string.format([[vim.fn.strdisplaywidth(%q)]], r))
  MiniTest.expect.equality(width <= 30, true)
end

-- ── reset ──────────────────────────────────────────────────────

T["reset"] = MiniTest.new_set()

T["reset"]["resets marquee state without error"] = function()
  child.lua([[statusline.reset()]])
  MiniTest.expect.equality(true, true)
end

-- ── tick ────────────────────────────────────────────────────────

T["tick"] = MiniTest.new_set()

T["tick"]["returns false when inactive"] = function()
  child.lua([[state.current = { status = "inactive" }]])
  local changed = child.lua_get([[statusline.tick()]])
  MiniTest.expect.equality(changed, false)
end

T["tick"]["returns boolean value"] = function()
  H.set_state(child, H.make_state({ status = "playing" }))
  local r = child.lua_get([[type(statusline.tick())]])
  MiniTest.expect.equality(r, "boolean")
end

-- ── elements config ────────────────────────────────────────────

T["elements"] = MiniTest.new_set()

T["elements"]["hides player when disabled"] = function()
  child.lua([[
    require("player.config").setup({
      statusline = { elements = { player = false, status_icon = true, track_title = true, artist = true } }
    })
  ]])
  H.set_state(child, H.make_state({ status = "playing", player = "spotify" }))
  local r = child.lua_get([[statusline.statusline()]])
  -- Should NOT have the player bracket [Spotify]
  MiniTest.expect.equality(r:find("%[.*Spotify.*%]") == nil, true)
end

T["elements"]["hides status icon when disabled"] = function()
  child.lua([[
    require("player.config").setup({
      statusline = { elements = { player = false, status_icon = false, track_title = true, artist = true } }
    })
  ]])
  H.set_state(child, H.make_state({ status = "playing" }))
  local r = child.lua_get([[statusline.statusline()]])
  -- Should NOT have ▶ or ⏸
  MiniTest.expect.equality(r:find("▶") == nil, true)
  MiniTest.expect.equality(r:find("⏸") == nil, true)
end

return T
