-- Unit tests for lua/player/state.lua
-- Tests state management, tick logic, listeners, and module interface.
local H = dofile("tests/helpers.lua")

local T = MiniTest.new_set({
  hooks = {
    pre_once = function()
      _G.child = H.new_child()
      H.setup_plugin(child, {})
      child.lua([[_G.state = require("player.state")]])
    end,
    post_once = function()
      child.stop()
    end,
    pre_case = function()
      child.lua([[
        package.loaded["player.state"] = nil
        _G.state = require("player.state")
      ]])
    end,
  },
})

-- ── module interface ───────────────────────────────────────────

T["module"] = MiniTest.new_set()

T["module"]["exports expected functions"] = function()
  local keys = child.lua_get([[(function()
    local fns = {}
    for k, v in pairs(state) do
      if type(v) == "function" then
        table.insert(fns, k)
      end
    end
    table.sort(fns)
    return fns
  end)()]])
  MiniTest.expect.equality(vim.tbl_contains(keys, "refresh"), true)
  MiniTest.expect.equality(vim.tbl_contains(keys, "play_pause"), true)
  MiniTest.expect.equality(vim.tbl_contains(keys, "next_track"), true)
  MiniTest.expect.equality(vim.tbl_contains(keys, "previous_track"), true)
  MiniTest.expect.equality(vim.tbl_contains(keys, "stop"), true)
  MiniTest.expect.equality(vim.tbl_contains(keys, "seek"), true)
  MiniTest.expect.equality(vim.tbl_contains(keys, "volume_up"), true)
  MiniTest.expect.equality(vim.tbl_contains(keys, "volume_down"), true)
  MiniTest.expect.equality(vim.tbl_contains(keys, "tick"), true)
  MiniTest.expect.equality(vim.tbl_contains(keys, "on_change"), true)
  MiniTest.expect.equality(vim.tbl_contains(keys, "set_provider"), true)
  MiniTest.expect.equality(vim.tbl_contains(keys, "providers"), true)
end

-- ── initial state ──────────────────────────────────────────────

T["initial state"] = MiniTest.new_set()

T["initial state"]["current is inactive on load"] = function()
  local s = child.lua_get([[state.current]])
  MiniTest.expect.equality(s.status, "inactive")
end

T["initial state"]["current has nil track"] = function()
  local track = child.lua_get([[state.current.track]])
  MiniTest.expect.equality(track, vim.NIL)
end

-- ── tick ────────────────────────────────────────────────────────

T["tick"] = MiniTest.new_set()

T["tick"]["does nothing when status is inactive"] = function()
  child.lua([[state.current = { status = "inactive", track = nil }]])
  local result = child.lua_get([[state.tick(1)]])
  MiniTest.expect.equality(result.status, "inactive")
end

T["tick"]["does nothing when status is paused"] = function()
  child.lua([[
    state.current = {
      status = "paused",
      track = { title = "Test", duration = 240 },
      position = 100,
    }
  ]])
  child.lua([[state.tick(1)]])
  local pos = child.lua_get([[state.current.position]])
  MiniTest.expect.equality(pos, 100)
end

T["tick"]["advances position by delta when playing"] = function()
  child.lua([[
    state.current = {
      status = "playing",
      track = { title = "Test", duration = 240 },
      position = 100,
    }
  ]])
  child.lua([[state.tick(3)]])
  local pos = child.lua_get([[state.current.position]])
  MiniTest.expect.equality(pos, 103)
end

T["tick"]["defaults to delta of 1"] = function()
  child.lua([[
    state.current = {
      status = "playing",
      track = { title = "Test", duration = 240 },
      position = 50,
    }
  ]])
  child.lua([[state.tick()]])
  local pos = child.lua_get([[state.current.position]])
  MiniTest.expect.equality(pos, 51)
end

T["tick"]["clamps at track duration"] = function()
  child.lua([[
    state.current = {
      status = "playing",
      track = { title = "Test", duration = 100 },
      position = 99,
    }
  ]])
  child.lua([[state.tick(5)]])
  local pos = child.lua_get([[state.current.position]])
  MiniTest.expect.equality(pos, 100)
end

T["tick"]["returns current state when no duration"] = function()
  child.lua([[
    state.current = {
      status = "playing",
      track = { title = "Test" },
      position = 50,
    }
  ]])
  child.lua([[state.tick(1)]])
  local pos = child.lua_get([[state.current.position]])
  MiniTest.expect.equality(pos, 50)
end

T["tick"]["returns current state when duration is zero"] = function()
  child.lua([[
    state.current = {
      status = "playing",
      track = { title = "Test", duration = 0 },
      position = 50,
    }
  ]])
  child.lua([[state.tick(1)]])
  local pos = child.lua_get([[state.current.position]])
  MiniTest.expect.equality(pos, 50)
end

-- ── on_change / listeners ──────────────────────────────────────

T["on_change"] = MiniTest.new_set()

T["on_change"]["tick emits to listeners"] = function()
  local emitted = child.lua_get([[(function()
    local received = false
    state.on_change(function(s)
      received = true
    end)
    state.current = {
      status = "playing",
      track = { title = "Test", duration = 240 },
      position = 50,
    }
    state.tick(1)
    return received
  end)()]])
  MiniTest.expect.equality(emitted, true)
end

-- ── providers list ─────────────────────────────────────────────

T["providers"] = MiniTest.new_set()

T["providers"]["returns a sorted list of provider names"] = function()
  local names = child.lua_get([[state.providers()]])
  MiniTest.expect.equality(type(names), "table")
  -- Should be sorted
  for i = 2, #names do
    MiniTest.expect.equality(names[i - 1] <= names[i], true)
  end
end

-- ── refresh without providers ──────────────────────────────────

T["refresh"] = MiniTest.new_set()

T["refresh"]["returns a state table or nil"] = function()
  -- On a macOS dev machine, providers like macos_media may be available
  -- and return a real status. We just verify refresh() doesn't crash
  -- and returns a table with a status field (or nil with an error).
  local result = child.lua_get([[(function()
    local s, err = state.refresh()
    if not s then
      return "nil_result"
    end
    if type(s) == "table" and s.status then
      return "ok"
    end
    return "unexpected"
  end)()]])
  MiniTest.expect.equality(
    result == "ok" or result == "nil_result",
    true
  )
end

return T
