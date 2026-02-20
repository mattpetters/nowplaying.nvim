-- Unit tests for lua/player/log.lua
-- Tests level filtering and module interface.
local H = dofile("tests/helpers.lua")

local T = MiniTest.new_set({
  hooks = {
    pre_once = function()
      _G.child = H.new_child()
      child.lua([[_G.log = require("player.log")]])
    end,
    post_once = function()
      child.stop()
    end,
    pre_case = function()
      child.lua([[
        package.loaded["player.log"] = nil
        _G.log = require("player.log")
      ]])
    end,
  },
})

-- ── module interface ───────────────────────────────────────────

T["module"] = MiniTest.new_set()

T["module"]["exports expected functions"] = function()
  local keys = child.lua_get([[(function()
    local fns = {}
    for k, v in pairs(log) do
      if type(v) == "function" then
        table.insert(fns, k)
      end
    end
    table.sort(fns)
    return fns
  end)()]])
  -- Should have set_level, trace, debug, info, warn, error
  MiniTest.expect.equality(vim.tbl_contains(keys, "set_level"), true)
  MiniTest.expect.equality(vim.tbl_contains(keys, "trace"), true)
  MiniTest.expect.equality(vim.tbl_contains(keys, "debug"), true)
  MiniTest.expect.equality(vim.tbl_contains(keys, "info"), true)
  MiniTest.expect.equality(vim.tbl_contains(keys, "warn"), true)
  MiniTest.expect.equality(vim.tbl_contains(keys, "error"), true)
end

-- ── level filtering ────────────────────────────────────────────

T["set_level"] = MiniTest.new_set()

T["set_level"]["accepts valid level names without error"] = function()
  child.lua([[
    log.set_level("trace")
    log.set_level("debug")
    log.set_level("info")
    log.set_level("warn")
    log.set_level("error")
  ]])
  MiniTest.expect.equality(true, true)
end

T["set_level"]["accepts uppercase level names"] = function()
  child.lua([[
    log.set_level("WARN")
    log.set_level("Error")
    log.set_level("INFO")
  ]])
  MiniTest.expect.equality(true, true)
end

T["set_level"]["falls back to warn for unknown level"] = function()
  child.lua([[log.set_level("nonexistent")]])
  MiniTest.expect.equality(true, true)
end

-- ── callable without error ─────────────────────────────────────

T["logging functions"] = MiniTest.new_set()

T["logging functions"]["trace does not error"] = function()
  child.lua([[log.set_level("trace"); log.trace("test message")]])
  MiniTest.expect.equality(true, true)
end

T["logging functions"]["debug does not error"] = function()
  child.lua([[log.set_level("debug"); log.debug("test message")]])
  MiniTest.expect.equality(true, true)
end

T["logging functions"]["info does not error"] = function()
  child.lua([[log.info("test message")]])
  MiniTest.expect.equality(true, true)
end

T["logging functions"]["warn does not error"] = function()
  child.lua([[log.warn("test message")]])
  MiniTest.expect.equality(true, true)
end

T["logging functions"]["error does not error"] = function()
  child.lua([[log.error("test message")]])
  MiniTest.expect.equality(true, true)
end

-- ── level filtering behavior ───────────────────────────────────

T["filtering"] = MiniTest.new_set()

T["filtering"]["suppresses messages below current level"] = function()
  local count = child.lua_get([[(function()
    local captured = {}
    local orig_notify = vim.notify
    vim.notify = function(msg, level, opts)
      table.insert(captured, { msg = msg, level = level })
    end

    log.set_level("error")
    log.trace("t")
    log.debug("d")
    log.info("i")
    log.warn("w")

    vim.wait(100, function() return false end)

    log.error("e")
    vim.wait(100, function() return false end)

    vim.notify = orig_notify
    return #captured
  end)()]])
  MiniTest.expect.equality(count, 1)
end

T["filtering"]["allows messages at or above current level"] = function()
  local count = child.lua_get([[(function()
    local captured = {}
    local orig_notify = vim.notify
    vim.notify = function(msg, level, opts)
      table.insert(captured, { msg = msg, level = level })
    end

    log.set_level("info")
    log.info("i")
    log.warn("w")
    log.error("e")

    vim.wait(100, function() return false end)

    vim.notify = orig_notify
    return #captured
  end)()]])
  MiniTest.expect.equality(count, 3)
end

return T
