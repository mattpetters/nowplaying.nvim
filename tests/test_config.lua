-- Unit tests for player.config module
local H = dofile("tests/helpers.lua")

local T = MiniTest.new_set({
  hooks = {
    pre_once = function()
      _G.child = H.new_child()
    end,
    post_once = function()
      child.stop()
    end,
    -- Re-initialise config before each test to avoid cross-contamination
    pre_case = function()
      child.lua([[package.loaded["player.config"] = nil]])
    end,
  },
})

-- ── Defaults ───────────────────────────────────────────────────

T["defaults"] = MiniTest.new_set()

T["defaults"]["panel is enabled by default"] = function()
  child.lua([[require("player.config").setup({})]])
  local enabled = child.lua_get([[require("player.config").get().panel.enabled]])
  MiniTest.expect.equality(enabled, true)
end

T["defaults"]["panel draggable is true by default"] = function()
  child.lua([[require("player.config").setup({})]])
  local draggable = child.lua_get([[require("player.config").get().panel.draggable]])
  MiniTest.expect.equality(draggable, true)
end

T["defaults"]["panel border is rounded by default"] = function()
  child.lua([[require("player.config").setup({})]])
  local border = child.lua_get([[require("player.config").get().panel.border]])
  MiniTest.expect.equality(border, "rounded")
end

T["defaults"]["panel width and height are nil by default"] = function()
  child.lua([[require("player.config").setup({})]])
  local width = child.lua_get([[require("player.config").get().panel.width]])
  local height = child.lua_get([[require("player.config").get().panel.height]])
  MiniTest.expect.equality(width, vim.NIL)
  MiniTest.expect.equality(height, vim.NIL)
end

-- ── Overrides ──────────────────────────────────────────────────

T["overrides"] = MiniTest.new_set()

T["overrides"]["user can disable draggable"] = function()
  child.lua([[require("player.config").setup({ panel = { draggable = false } })]])
  local draggable = child.lua_get([[require("player.config").get().panel.draggable]])
  MiniTest.expect.equality(draggable, false)
end

T["overrides"]["user can set custom dimensions"] = function()
  child.lua([[require("player.config").setup({ panel = { width = 80, height = 20 } })]])
  local width = child.lua_get([[require("player.config").get().panel.width]])
  local height = child.lua_get([[require("player.config").get().panel.height]])
  MiniTest.expect.equality(width, 80)
  MiniTest.expect.equality(height, 20)
end

T["overrides"]["user can disable panel entirely"] = function()
  child.lua([[require("player.config").setup({ panel = { enabled = false } })]])
  local enabled = child.lua_get([[require("player.config").get().panel.enabled]])
  MiniTest.expect.equality(enabled, false)
end

T["overrides"]["deep extends nested element config"] = function()
  child.lua([[
    require("player.config").setup({
      panel = { elements = { artwork = { width = 30, height = 15 } } }
    })
  ]])
  local art_w = child.lua_get([[require("player.config").get().panel.elements.artwork.width]])
  local art_h = child.lua_get([[require("player.config").get().panel.elements.artwork.height]])
  MiniTest.expect.equality(art_w, 30)
  MiniTest.expect.equality(art_h, 15)
  -- Verify other defaults preserved
  local track_title = child.lua_get([[require("player.config").get().panel.elements.track_title]])
  MiniTest.expect.equality(track_title, true)
end

return T
