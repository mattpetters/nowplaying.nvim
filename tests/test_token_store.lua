-- Unit tests for player.spotify_api.token_store
-- Tests token persistence, expiry checking, store/get/clear lifecycle.
local H = dofile("tests/helpers.lua")

local T = MiniTest.new_set({
  hooks = {
    pre_once = function()
      _G.child = H.new_child()
    end,
    post_once = function()
      child.stop()
    end,
    pre_case = function()
      -- Fresh module + clean any leftover tokens
      child.lua([[
        package.loaded["player.config"] = nil
        package.loaded["player.spotify_api.token_store"] = nil
        require("player.config").setup({})
        _G.ts = require("player.spotify_api.token_store")
        -- Clear any leftover tokens from previous tests
        ts.clear()
      ]])
    end,
  },
})

-- ── Initial state ──────────────────────────────────────────────

T["initial"] = MiniTest.new_set()

T["initial"]["has_tokens returns false when no tokens stored"] = function()
  local result = child.lua_get([[ts.has_tokens()]])
  MiniTest.expect.equality(result, false)
end

T["initial"]["get returns nil when no tokens stored"] = function()
  local result = child.lua_get([[ts.get()]])
  MiniTest.expect.equality(result, vim.NIL)
end

T["initial"]["access_token returns nil when no tokens stored"] = function()
  local result = child.lua_get([[ts.access_token()]])
  MiniTest.expect.equality(result, vim.NIL)
end

T["initial"]["refresh_token returns nil when no tokens stored"] = function()
  local result = child.lua_get([[ts.refresh_token()]])
  MiniTest.expect.equality(result, vim.NIL)
end

T["initial"]["is_expired returns true when no tokens stored"] = function()
  local result = child.lua_get([[ts.is_expired()]])
  MiniTest.expect.equality(result, true)
end

-- ── store / get lifecycle ──────────────────────────────────────

T["store"] = MiniTest.new_set()

T["store"]["stores and retrieves tokens"] = function()
  child.lua([[
    ts.store({
      access_token = "test_access_123",
      refresh_token = "test_refresh_456",
      expires_in = 3600,
      scope = "user-read-playback-state",
      token_type = "Bearer",
    })
  ]])
  local access = child.lua_get([[ts.access_token()]])
  MiniTest.expect.equality(access, "test_access_123")

  local refresh = child.lua_get([[ts.refresh_token()]])
  MiniTest.expect.equality(refresh, "test_refresh_456")
end

T["store"]["has_tokens returns true after store"] = function()
  child.lua([[
    ts.store({
      access_token = "abc",
      refresh_token = "def",
      expires_in = 3600,
    })
  ]])
  local result = child.lua_get([[ts.has_tokens()]])
  MiniTest.expect.equality(result, true)
end

T["store"]["get returns full token table"] = function()
  child.lua([[
    ts.store({
      access_token = "token_a",
      refresh_token = "token_r",
      expires_in = 3600,
      scope = "user-modify-playback-state",
      token_type = "Bearer",
    })
  ]])
  local data = child.lua_get([[ts.get()]])
  MiniTest.expect.equality(data.access_token, "token_a")
  MiniTest.expect.equality(data.refresh_token, "token_r")
  MiniTest.expect.equality(data.scope, "user-modify-playback-state")
  MiniTest.expect.equality(data.token_type, "Bearer")
  MiniTest.expect.equality(type(data.expires_at), "number")
  MiniTest.expect.equality(type(data.stored_at), "number")
end

T["store"]["computes expires_at with 60s buffer"] = function()
  local result = child.lua_get([[
    (function()
      local before = os.time()
      ts.store({ access_token = "x", expires_in = 3600 })
      local data = ts.get()
      local after = os.time()
      -- expires_at should be approximately now + 3600 - 60
      local expected_min = before + 3600 - 60
      local expected_max = after + 3600 - 60
      return data.expires_at >= expected_min and data.expires_at <= expected_max
    end)()
  ]])
  MiniTest.expect.equality(result, true)
end

T["store"]["preserves existing refresh_token when new data lacks one"] = function()
  child.lua([[
    ts.store({
      access_token = "first_access",
      refresh_token = "original_refresh",
      expires_in = 3600,
    })
    -- Simulate a refresh response that doesn't include refresh_token
    ts.store({
      access_token = "new_access",
      expires_in = 3600,
    })
  ]])
  local refresh = child.lua_get([[ts.refresh_token()]])
  MiniTest.expect.equality(refresh, "original_refresh")

  local access = child.lua_get([[ts.access_token()]])
  MiniTest.expect.equality(access, "new_access")
end

T["store"]["defaults token_type to Bearer"] = function()
  child.lua([[
    ts.store({ access_token = "x", expires_in = 3600 })
  ]])
  local tt = child.lua_get([[ts.get().token_type]])
  MiniTest.expect.equality(tt, "Bearer")
end

T["store"]["defaults expires_in to 3600 when missing"] = function()
  local result = child.lua_get([[
    (function()
      local before = os.time()
      ts.store({ access_token = "x" })
      local data = ts.get()
      -- Should default to 3600 - 60 = 3540 seconds from now
      return data.expires_at >= before + 3540 - 1
    end)()
  ]])
  MiniTest.expect.equality(result, true)
end

-- ── Expiry ─────────────────────────────────────────────────────

T["expiry"] = MiniTest.new_set()

T["expiry"]["is_expired returns false for fresh token"] = function()
  child.lua([[
    ts.store({ access_token = "x", expires_in = 3600 })
  ]])
  local result = child.lua_get([[ts.is_expired()]])
  MiniTest.expect.equality(result, false)
end

T["expiry"]["is_expired returns true for expired token"] = function()
  -- Directly set expires_at in the past by manipulating stored data
  child.lua([[
    ts.store({ access_token = "x", expires_in = 0 })
  ]])
  -- expires_in = 0 means expires_at = now - 60, which is in the past
  local result = child.lua_get([[ts.is_expired()]])
  MiniTest.expect.equality(result, true)
end

-- ── Clear ──────────────────────────────────────────────────────

T["clear"] = MiniTest.new_set()

T["clear"]["removes tokens from memory"] = function()
  child.lua([[
    ts.store({ access_token = "x", refresh_token = "y", expires_in = 3600 })
    ts.clear()
  ]])
  local result = child.lua_get([[ts.has_tokens()]])
  MiniTest.expect.equality(result, false)
end

T["clear"]["access_token returns nil after clear"] = function()
  child.lua([[
    ts.store({ access_token = "x", expires_in = 3600 })
    ts.clear()
  ]])
  local result = child.lua_get([[ts.access_token()]])
  MiniTest.expect.equality(result, vim.NIL)
end

T["clear"]["get returns nil after clear"] = function()
  child.lua([[
    ts.store({ access_token = "x", expires_in = 3600 })
    ts.clear()
  ]])
  local result = child.lua_get([[ts.get()]])
  MiniTest.expect.equality(result, vim.NIL)
end

-- ── Disk persistence ───────────────────────────────────────────

T["persistence"] = MiniTest.new_set()

T["persistence"]["tokens survive module reload"] = function()
  child.lua([[
    ts.store({
      access_token = "persist_test",
      refresh_token = "persist_refresh",
      expires_in = 3600,
    })
    -- Force module reload
    package.loaded["player.spotify_api.token_store"] = nil
    _G.ts = require("player.spotify_api.token_store")
  ]])
  local access = child.lua_get([[ts.access_token()]])
  MiniTest.expect.equality(access, "persist_test")

  -- Clean up
  child.lua([[ts.clear()]])
end

T["persistence"]["clear removes token file from disk"] = function()
  child.lua([[
    ts.store({ access_token = "x", expires_in = 3600 })
    ts.clear()
    -- Reload module to verify file is gone
    package.loaded["player.spotify_api.token_store"] = nil
    _G.ts = require("player.spotify_api.token_store")
  ]])
  local result = child.lua_get([[ts.has_tokens()]])
  MiniTest.expect.equality(result, false)
end

return T
