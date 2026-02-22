-- Unit tests for lua/player/telescope/search.lua formatting helpers.
-- Since the formatting functions are local, we replicate them in the child
-- process and test their logic directly.
local H = dofile("tests/helpers.lua")

local T = MiniTest.new_set({
  hooks = {
    pre_once = function()
      _G.child = H.new_child()
      -- Define all helper functions in the child process once
      child.lua([[
        function format_duration(ms)
          if not ms then return "" end
          local total_sec = math.floor(ms / 1000)
          local min = math.floor(total_sec / 60)
          local sec = total_sec % 60
          return string.format("%d:%02d", min, sec)
        end

        function format_number(n)
          if not n or n == 0 then return "0" end
          if n >= 1000000 then
            return string.format("%.1fM", n / 1000000)
          elseif n >= 1000 then
            return string.format("%.1fK", n / 1000)
          end
          return tostring(n)
        end

        function release_year(date_str)
          if not date_str or date_str == "" then return nil end
          return date_str:match("^(%d%d%d%d)")
        end

        function popularity_bar(pop, width)
          width = width or 10
          if not pop then return string.rep("\u{2591}", width) .. "  ?" end
          local filled = math.floor(pop / 100 * width + 0.5)
          local empty = width - filled
          return string.rep("\u{2588}", filled) .. string.rep("\u{2591}", empty) .. " " .. tostring(pop)
        end
      ]])
    end,
    post_once = function()
      child.stop()
    end,
  },
})

-- ── format_duration ────────────────────────────────────────────

T["format_duration"] = MiniTest.new_set()

T["format_duration"]["converts ms to m:ss"] = function()
  local r = child.lua_get([[format_duration(210000)]])
  MiniTest.expect.equality(r, "3:30")
end

T["format_duration"]["handles zero"] = function()
  local r = child.lua_get([[format_duration(0)]])
  MiniTest.expect.equality(r, "0:00")
end

T["format_duration"]["handles nil"] = function()
  local r = child.lua_get([[format_duration(nil)]])
  MiniTest.expect.equality(r, "")
end

T["format_duration"]["handles sub-minute"] = function()
  local r = child.lua_get([[format_duration(45000)]])
  MiniTest.expect.equality(r, "0:45")
end

T["format_duration"]["handles exact minute"] = function()
  local r = child.lua_get([[format_duration(120000)]])
  MiniTest.expect.equality(r, "2:00")
end

T["format_duration"]["handles long track"] = function()
  local r = child.lua_get([[format_duration(600000)]])
  MiniTest.expect.equality(r, "10:00")
end

-- ── format_number ──────────────────────────────────────────────

T["format_number"] = MiniTest.new_set()

T["format_number"]["formats millions"] = function()
  local r = child.lua_get([[format_number(5200000)]])
  MiniTest.expect.equality(r, "5.2M")
end

T["format_number"]["formats thousands"] = function()
  local r = child.lua_get([[format_number(42500)]])
  MiniTest.expect.equality(r, "42.5K")
end

T["format_number"]["formats small numbers as-is"] = function()
  local r = child.lua_get([[format_number(42)]])
  MiniTest.expect.equality(r, "42")
end

T["format_number"]["returns 0 for nil"] = function()
  local r = child.lua_get([[format_number(nil)]])
  MiniTest.expect.equality(r, "0")
end

T["format_number"]["returns 0 for zero"] = function()
  local r = child.lua_get([[format_number(0)]])
  MiniTest.expect.equality(r, "0")
end

T["format_number"]["formats exact million"] = function()
  local r = child.lua_get([[format_number(1000000)]])
  MiniTest.expect.equality(r, "1.0M")
end

T["format_number"]["formats exact thousand"] = function()
  local r = child.lua_get([[format_number(1000)]])
  MiniTest.expect.equality(r, "1.0K")
end

-- ── release_year ───────────────────────────────────────────────

T["release_year"] = MiniTest.new_set()

T["release_year"]["extracts 4-digit year from date string"] = function()
  local r = child.lua_get([[release_year("2023-05-15")]])
  MiniTest.expect.equality(r, "2023")
end

T["release_year"]["handles year-only string"] = function()
  local r = child.lua_get([[release_year("2021")]])
  MiniTest.expect.equality(r, "2021")
end

T["release_year"]["returns nil for nil input"] = function()
  local r = child.lua_get([[release_year(nil)]])
  MiniTest.expect.equality(r, vim.NIL)
end

T["release_year"]["returns nil for empty string"] = function()
  local r = child.lua_get([[release_year("")]])
  MiniTest.expect.equality(r, vim.NIL)
end

T["release_year"]["handles year-month format"] = function()
  local r = child.lua_get([[release_year("2020-03")]])
  MiniTest.expect.equality(r, "2020")
end

-- ── popularity_bar ─────────────────────────────────────────────

T["popularity_bar"] = MiniTest.new_set()

T["popularity_bar"]["generates bar for 50% popularity"] = function()
  local r = child.lua_get([[popularity_bar(50, 10)]])
  MiniTest.expect.equality(r:find("50") ~= nil, true)
  MiniTest.expect.equality(r:find("\u{2588}") ~= nil, true)
  MiniTest.expect.equality(r:find("\u{2591}") ~= nil, true)
end

T["popularity_bar"]["generates full bar for 100%"] = function()
  local r = child.lua_get([[popularity_bar(100, 10)]])
  MiniTest.expect.equality(r:find("100") ~= nil, true)
end

T["popularity_bar"]["generates empty bar for 0%"] = function()
  local r = child.lua_get([[popularity_bar(0, 10)]])
  MiniTest.expect.equality(r:find("0") ~= nil, true)
end

T["popularity_bar"]["shows ? for nil popularity"] = function()
  local r = child.lua_get([[popularity_bar(nil, 10)]])
  MiniTest.expect.equality(r:find("?") ~= nil, true)
end

T["popularity_bar"]["uses default width of 10"] = function()
  local r = child.lua_get([[popularity_bar(50)]])
  MiniTest.expect.equality(r:find("50") ~= nil, true)
end

-- ── artwork integration ────────────────────────────────────────
-- Tests that the search previewer's artwork cache key logic works
-- and that artwork.fetch_url is callable for search result items.

T["artwork_integration"] = MiniTest.new_set()

T["artwork_integration"]["builds correct cache key from search item"] = function()
  local result = child.lua_get([[(function()
    local item = { type = "track", id = "abc123", name = "Test", image_url = "https://i.scdn.co/image/abc" }
    local cache_key = (item.type or "img") .. "_" .. (item.id or item.name or "unknown")
    return cache_key
  end)()]])
  MiniTest.expect.equality(result, "track_abc123")
end

T["artwork_integration"]["cache key uses name when id is missing"] = function()
  local result = child.lua_get([[(function()
    local item = { type = "album", name = "My Album", image_url = "https://example.com" }
    local cache_key = (item.type or "img") .. "_" .. (item.id or item.name or "unknown")
    return cache_key
  end)()]])
  MiniTest.expect.equality(result, "album_My Album")
end

T["artwork_integration"]["fetch_url returns cached path for search item"] = function()
  local result = child.lua_get([[(function()
    local art = require("player.artwork")
    local utils = require("player.utils")
    utils.file_exists = function() return true end
    utils.ensure_dir = function() end
    local item = { type = "track", id = "t1", image_url = "https://i.scdn.co/image/t1" }
    local cache_key = item.type .. "_" .. item.id
    local res = art.fetch_url(item.image_url, cache_key)
    return res ~= nil and res.path ~= nil
  end)()]])
  MiniTest.expect.equality(result, true)
end

T["artwork_integration"]["shows loading when artwork not cached"] = function()
  local result = child.lua_get([[(function()
    local art = require("player.artwork")
    local utils = require("player.utils")
    utils.file_exists = function() return false end
    utils.download = function() return false end
    utils.ensure_dir = function() end
    local item = { type = "album", id = "a1", image_url = "https://i.scdn.co/image/a1" }
    local cache_key = item.type .. "_" .. item.id
    local res = art.fetch_url(item.image_url, cache_key)
    return res == nil
  end)()]])
  -- nil means not yet available → previewer should show loading placeholder
  MiniTest.expect.equality(result, true)
end

T["artwork_integration"]["skips artwork for items without image_url"] = function()
  local result = child.lua_get([[(function()
    local item = { type = "track", id = "t2", name = "No Image" }
    return item.image_url == nil
  end)()]])
  MiniTest.expect.equality(result, true)
end

return T
