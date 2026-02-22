-- Unit tests for player.artwork shared cache module.
-- Tests both the existing provider-based fetch() and the new URL-based fetch_url().
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
      child.lua([[
        package.loaded["player.artwork"] = nil
        package.loaded["player.config"] = nil
        package.loaded["player.utils"] = nil
        package.loaded["player.log"] = nil
        require("player.config").setup({})
      ]])
    end,
  },
})

-- ── cache_path_for ─────────────────────────────────────────────

T["cache_path_for"] = MiniTest.new_set()

T["cache_path_for"]["returns path with slugified key"] = function()
  local result = child.lua_get([[(function()
    local artwork = require("player.artwork")
    return artwork.cache_path_for("My Album Art")
  end)()]])
  MiniTest.expect.equality(type(result), "string")
  MiniTest.expect.equality(result:find("my%-album%-art%.jpg") ~= nil, true)
end

T["cache_path_for"]["uses config cache_dir"] = function()
  local result = child.lua_get([[(function()
    require("player.config").setup({
      panel = { elements = { artwork = { cache_dir = "/tmp/test-artwork-cache" } } }
    })
    local artwork = require("player.artwork")
    return artwork.cache_path_for("test-key")
  end)()]])
  MiniTest.expect.equality(result:find("^/tmp/test%-artwork%-cache/") ~= nil, true)
end

T["cache_path_for"]["returns nil for nil key"] = function()
  local result = child.lua_get([[require("player.artwork").cache_path_for(nil)]])
  MiniTest.expect.equality(result, vim.NIL)
end

T["cache_path_for"]["returns nil for empty string key"] = function()
  local result = child.lua_get([[require("player.artwork").cache_path_for("")]])
  MiniTest.expect.equality(result, vim.NIL)
end

-- ── fetch_url ──────────────────────────────────────────────────

T["fetch_url"] = MiniTest.new_set()

T["fetch_url"]["returns nil when url is nil"] = function()
  local result = child.lua_get([[require("player.artwork").fetch_url(nil, "some-key") or "NIL"]])
  MiniTest.expect.equality(result, "NIL")
end

T["fetch_url"]["returns nil when cache_key is nil"] = function()
  local result = child.lua_get([[require("player.artwork").fetch_url("https://example.com/img.jpg", nil) or "NIL"]])
  MiniTest.expect.equality(result, "NIL")
end

T["fetch_url"]["returns cached result when file exists"] = function()
  local result = child.lua_get([[(function()
    local utils = require("player.utils")
    local artwork = require("player.artwork")
    utils.file_exists = function() return true end
    _G._download_called = false
    utils.download = function() _G._download_called = true; return true end
    local res = artwork.fetch_url("https://example.com/img.jpg", "cached-key")
    return { path_exists = res ~= nil and res.path ~= nil, download_called = _G._download_called }
  end)()]])
  MiniTest.expect.equality(result.path_exists, true)
  MiniTest.expect.equality(result.download_called, false)
end

T["fetch_url"]["calls download for new URLs"] = function()
  local result = child.lua_get([[(function()
    local utils = require("player.utils")
    local artwork = require("player.artwork")
    utils.file_exists = function() return false end
    _G._download_args = nil
    utils.download = function(url, path) _G._download_args = { url = url, path = path }; return true end
    utils.ensure_dir = function() end
    local res = artwork.fetch_url("https://i.scdn.co/image/abc123", "test-track")
    return { has_path = res ~= nil and res.path ~= nil, url = _G._download_args and _G._download_args.url }
  end)()]])
  MiniTest.expect.equality(result.has_path, true)
  MiniTest.expect.equality(result.url, "https://i.scdn.co/image/abc123")
end

T["fetch_url"]["returns nil on download failure"] = function()
  local result = child.lua_get([[(function()
    local utils = require("player.utils")
    local artwork = require("player.artwork")
    utils.file_exists = function() return false end
    utils.download = function() return false, "network error" end
    utils.ensure_dir = function() end
    return artwork.fetch_url("https://example.com/img.jpg", "fail-key") or "NIL"
  end)()]])
  MiniTest.expect.equality(result, "NIL")
end

T["fetch_url"]["uses slug for cache filename"] = function()
  local result = child.lua_get([[(function()
    local utils = require("player.utils")
    local artwork = require("player.artwork")
    utils.file_exists = function() return true end
    local res = artwork.fetch_url("https://example.com/img.jpg", "My Great Album")
    return res and res.path or "NIL"
  end)()]])
  MiniTest.expect.equality(type(result), "string")
  MiniTest.expect.equality(result:find("my%-great%-album%.jpg") ~= nil, true)
end

T["fetch_url"]["ensures cache directory exists"] = function()
  local result = child.lua_get([[(function()
    local utils = require("player.utils")
    local artwork = require("player.artwork")
    _G._ensure_dir_called = nil
    utils.ensure_dir = function(dir) _G._ensure_dir_called = dir end
    utils.file_exists = function() return true end
    artwork.fetch_url("https://example.com/img.jpg", "dir-test")
    return _G._ensure_dir_called ~= nil
  end)()]])
  MiniTest.expect.equality(result, true)
end

-- ── fetch (backward compat) ────────────────────────────────────

T["fetch_compat"] = MiniTest.new_set()

T["fetch_compat"]["returns nil with no provider"] = function()
  local result = child.lua_get([[require("player.artwork").fetch(nil, { title = "Test" }) or "NIL"]])
  MiniTest.expect.equality(result, "NIL")
end

T["fetch_compat"]["returns nil with provider missing get_artwork"] = function()
  local result = child.lua_get([[require("player.artwork").fetch({ name = "test" }, { title = "Test" }) or "NIL"]])
  MiniTest.expect.equality(result, "NIL")
end

T["fetch_compat"]["returns cached path when file exists"] = function()
  local result = child.lua_get([[(function()
    local utils = require("player.utils")
    local artwork = require("player.artwork")
    utils.file_exists = function() return true end
    utils.ensure_dir = function() end
    local provider = { name = "spotify", get_artwork = function() end }
    local res = artwork.fetch(provider, { title = "Song", artist = "Art", album = "Alb" })
    return res ~= nil and res.path ~= nil
  end)()]])
  MiniTest.expect.equality(result, true)
end

return T
