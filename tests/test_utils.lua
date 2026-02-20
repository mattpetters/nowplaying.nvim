-- Unit tests for lua/player/utils.lua
-- Tests pure utility functions: trim, split, slug, file_exists, format_provider, escape_osa
local H = dofile("tests/helpers.lua")

local T = MiniTest.new_set({
  hooks = {
    pre_once = function()
      _G.child = H.new_child()
      child.lua([[_G.utils = require("player.utils")]])
    end,
    post_once = function()
      child.stop()
    end,
    pre_case = function()
      child.lua([[
        package.loaded["player.utils"] = nil
        _G.utils = require("player.utils")
      ]])
    end,
  },
})

-- ── trim ───────────────────────────────────────────────────────

T["trim"] = MiniTest.new_set()

T["trim"]["removes leading whitespace"] = function()
  local r = child.lua_get([[utils.trim("  hello")]])
  MiniTest.expect.equality(r, "hello")
end

T["trim"]["removes trailing whitespace"] = function()
  local r = child.lua_get([[utils.trim("hello   ")]])
  MiniTest.expect.equality(r, "hello")
end

T["trim"]["removes both ends"] = function()
  local r = child.lua_get([[utils.trim("  hello world  ")]])
  MiniTest.expect.equality(r, "hello world")
end

T["trim"]["handles empty string"] = function()
  local r = child.lua_get([[utils.trim("")]])
  MiniTest.expect.equality(r, "")
end

T["trim"]["handles whitespace-only string"] = function()
  local r = child.lua_get([[utils.trim("   ")]])
  MiniTest.expect.equality(r, "")
end

T["trim"]["handles tabs and newlines"] = function()
  local r = child.lua_get([[utils.trim("\t hello \n")]])
  MiniTest.expect.equality(r, "hello")
end

-- ── split ──────────────────────────────────────────────────────

T["split"] = MiniTest.new_set()

T["split"]["splits by separator"] = function()
  local r = child.lua_get([[utils.split("a,b,c", ",")]])
  MiniTest.expect.equality(r, { "a", "b", "c" })
end

T["split"]["handles no separator found"] = function()
  local r = child.lua_get([[utils.split("abc", ",")]])
  MiniTest.expect.equality(r, { "abc" })
end

T["split"]["handles empty parts"] = function()
  local r = child.lua_get([[utils.split("a,,c", ",")]])
  MiniTest.expect.equality(r, { "a", "", "c" })
end

T["split"]["handles multi-char separator"] = function()
  local r = child.lua_get([[utils.split("a - b - c", " - ")]])
  MiniTest.expect.equality(r, { "a", "b", "c" })
end

-- ── slug ───────────────────────────────────────────────────────

T["slug"] = MiniTest.new_set()

T["slug"]["lowercases input"] = function()
  local r = child.lua_get([[utils.slug("Hello World")]])
  MiniTest.expect.equality(r, "hello-world")
end

T["slug"]["replaces spaces with hyphens"] = function()
  local r = child.lua_get([[utils.slug("foo bar baz")]])
  MiniTest.expect.equality(r, "foo-bar-baz")
end

T["slug"]["strips special characters"] = function()
  local r = child.lua_get([[utils.slug("Rock & Roll!")]])
  MiniTest.expect.equality(r, "rock-roll")
end

T["slug"]["collapses multiple hyphens"] = function()
  local r = child.lua_get([[utils.slug("a - - b")]])
  MiniTest.expect.equality(r, "a-b")
end

T["slug"]["handles already-clean input"] = function()
  local r = child.lua_get([[utils.slug("clean")]])
  MiniTest.expect.equality(r, "clean")
end

T["slug"]["handles numbers"] = function()
  local r = child.lua_get([[utils.slug("Track 42")]])
  MiniTest.expect.equality(r, "track-42")
end

-- ── escape_osa ─────────────────────────────────────────────────

T["escape_osa"] = MiniTest.new_set()

T["escape_osa"]["escapes double quotes"] = function()
  local r = child.lua_get([[utils.escape_osa('say "hello"')]])
  MiniTest.expect.equality(r, 'say \\"hello\\"')
end

T["escape_osa"]["returns same string without quotes"] = function()
  local r = child.lua_get([[utils.escape_osa("no quotes here")]])
  MiniTest.expect.equality(r, "no quotes here")
end

T["escape_osa"]["handles nil input"] = function()
  local r = child.lua_get([[utils.escape_osa(nil)]])
  MiniTest.expect.equality(r, "")
end

T["escape_osa"]["handles empty string"] = function()
  local r = child.lua_get([[utils.escape_osa("")]])
  MiniTest.expect.equality(r, "")
end

-- ── format_provider ────────────────────────────────────────────

T["format_provider"] = MiniTest.new_set()

T["format_provider"]["returns known label for apple_music"] = function()
  local r = child.lua_get([[utils.format_provider("apple_music")]])
  -- Contains "Apple Music" (with the Nerd Font icon)
  MiniTest.expect.equality(r:find("Apple Music") ~= nil, true)
end

T["format_provider"]["returns known label for spotify"] = function()
  local r = child.lua_get([[utils.format_provider("spotify")]])
  MiniTest.expect.equality(r:find("Spotify") ~= nil, true)
end

T["format_provider"]["returns known label for macos_media"] = function()
  local r = child.lua_get([[utils.format_provider("macos_media")]])
  MiniTest.expect.equality(r:find("Now Playing") ~= nil, true)
end

T["format_provider"]["capitalizes unknown provider"] = function()
  local r = child.lua_get([[utils.format_provider("my_custom_player")]])
  MiniTest.expect.equality(r, "My Custom Player")
end

T["format_provider"]["handles nil input"] = function()
  local r = child.lua_get([[utils.format_provider(nil)]])
  MiniTest.expect.equality(r, "player")
end

T["format_provider"]["handles empty string"] = function()
  local r = child.lua_get([[utils.format_provider("")]])
  MiniTest.expect.equality(r, "player")
end

-- ── file_exists ────────────────────────────────────────────────

T["file_exists"] = MiniTest.new_set()

T["file_exists"]["returns true for existing file"] = function()
  -- The helpers file should always exist
  local r = child.lua_get(string.format(
    [[require("player.utils").file_exists(%q)]],
    H.project_root .. "/tests/helpers.lua"
  ))
  MiniTest.expect.equality(r, true)
end

T["file_exists"]["returns false for non-existent file"] = function()
  local r = child.lua_get([[require("player.utils").file_exists("/tmp/surely_does_not_exist_12345.xyz")]])
  -- file_exists returns nil (vim.NIL) for non-existent files, not false
  MiniTest.expect.equality(r == false or r == vim.NIL, true)
end

return T
