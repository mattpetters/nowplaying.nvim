-- Unit tests for lua/player/ui/notify.lua
-- Tests notification message formatting and show behavior.
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
        package.loaded["player.ui.notify"] = nil
        require("player.config").setup({})
        _G.notify_mod = require("player.ui.notify")
      ]])
    end,
  },
})

-- ── format_message (via show with captured vim.notify) ─────────

T["show"] = MiniTest.new_set()

T["show"]["does nothing when notify is disabled"] = function()
  child.lua([[require("player.config").setup({ notify = { enabled = false } })]])
  child.lua([[package.loaded["player.ui.notify"] = nil; _G.notify_mod = require("player.ui.notify")]])
  local called = child.lua_get([[(function()
    local captured = {}
    local orig = vim.notify
    vim.notify = function(msg, lvl, opts) table.insert(captured, msg) end
    notify_mod.show({ status = "playing", track = { title = "Test" } })
    vim.notify = orig
    return #captured
  end)()]])
  MiniTest.expect.equality(called, 0)
end

T["show"]["calls vim.notify when enabled"] = function()
  child.lua([[require("player.config").setup({ notify = { enabled = true } })]])
  child.lua([[package.loaded["player.ui.notify"] = nil; _G.notify_mod = require("player.ui.notify")]])
  local called = child.lua_get([[(function()
    local captured = {}
    local orig = vim.notify
    vim.notify = function(msg, lvl, opts) table.insert(captured, msg) end
    notify_mod.show({ status = "playing", track = { title = "Test" } })
    vim.notify = orig
    return #captured
  end)()]])
  MiniTest.expect.equality(called, 1)
end

T["show"]["includes track title in message"] = function()
  child.lua([[require("player.config").setup({ notify = { enabled = true } })]])
  child.lua([[package.loaded["player.ui.notify"] = nil; _G.notify_mod = require("player.ui.notify")]])
  local msg = child.lua_get([[(function()
    local captured = nil
    local orig = vim.notify
    vim.notify = function(m, lvl, opts) captured = m end
    notify_mod.show({
      status = "playing",
      track = { title = "My Song", artist = "The Band", album = "Great Album" },
      player = "spotify",
    })
    vim.notify = orig
    return captured
  end)()]])
  MiniTest.expect.equality(type(msg), "string")
  MiniTest.expect.equality(msg:find("My Song") ~= nil, true)
end

T["show"]["includes artist when element enabled"] = function()
  child.lua([[require("player.config").setup({
    notify = { enabled = true, elements = { status_icon = true, track_title = true, artist = true, album = false, player = false } }
  })]])
  child.lua([[package.loaded["player.ui.notify"] = nil; _G.notify_mod = require("player.ui.notify")]])
  local msg = child.lua_get([[(function()
    local captured = nil
    local orig = vim.notify
    vim.notify = function(m, lvl, opts) captured = m end
    notify_mod.show({
      status = "playing",
      track = { title = "Song", artist = "Artist Name", album = "Album" },
      player = "spotify",
    })
    vim.notify = orig
    return captured
  end)()]])
  MiniTest.expect.equality(msg:find("Artist Name") ~= nil, true)
end

T["show"]["shows inactive message for nil state"] = function()
  child.lua([[require("player.config").setup({ notify = { enabled = true } })]])
  child.lua([[package.loaded["player.ui.notify"] = nil; _G.notify_mod = require("player.ui.notify")]])
  local msg = child.lua_get([[(function()
    local captured = nil
    local orig = vim.notify
    vim.notify = function(m, lvl, opts) captured = m end
    notify_mod.show(nil)
    vim.notify = orig
    return captured
  end)()]])
  MiniTest.expect.equality(msg, "No active player")
end

T["show"]["shows inactive message for inactive status"] = function()
  child.lua([[require("player.config").setup({ notify = { enabled = true } })]])
  child.lua([[package.loaded["player.ui.notify"] = nil; _G.notify_mod = require("player.ui.notify")]])
  local msg = child.lua_get([[(function()
    local captured = nil
    local orig = vim.notify
    vim.notify = function(m, lvl, opts) captured = m end
    notify_mod.show({ status = "inactive" })
    vim.notify = orig
    return captured
  end)()]])
  MiniTest.expect.equality(msg, "No active player")
end

T["show"]["includes play icon for playing state"] = function()
  child.lua([[require("player.config").setup({ notify = { enabled = true } })]])
  child.lua([[package.loaded["player.ui.notify"] = nil; _G.notify_mod = require("player.ui.notify")]])
  local msg = child.lua_get([[(function()
    local captured = nil
    local orig = vim.notify
    vim.notify = function(m, lvl, opts) captured = m end
    notify_mod.show({ status = "playing", track = { title = "Test" } })
    vim.notify = orig
    return captured
  end)()]])
  MiniTest.expect.equality(msg:find("\xe2\x96\xb6") ~= nil, true)
end

T["show"]["includes pause icon for paused state"] = function()
  child.lua([[require("player.config").setup({ notify = { enabled = true } })]])
  child.lua([[package.loaded["player.ui.notify"] = nil; _G.notify_mod = require("player.ui.notify")]])
  local msg = child.lua_get([[(function()
    local captured = nil
    local orig = vim.notify
    vim.notify = function(m, lvl, opts) captured = m end
    notify_mod.show({ status = "paused", track = { title = "Test" } })
    vim.notify = orig
    return captured
  end)()]])
  MiniTest.expect.equality(msg:find("\xe2\x8f\xb8") ~= nil, true)
end

return T
