-- Unit tests for the macos_media provider
-- Tests the output parsing, status mapping, and artwork handling.
-- The actual CLI binary (nowplaying-cli) is NOT required for these tests;
-- we test the pure parsing functions directly.
local H = dofile("tests/helpers.lua")

local T = MiniTest.new_set({
  hooks = {
    pre_once = function()
      _G.child = H.new_child()
      -- Load the module under test
      child.lua([[_G.mm = require("player.providers.macos_media")]])
    end,
    post_once = function()
      child.stop()
    end,
    pre_case = function()
      -- Re-load fresh for each test
      child.lua([[
        package.loaded["player.providers.macos_media"] = nil
        _G.mm = require("player.providers.macos_media")
      ]])
    end,
  },
})

-- ── Module basics ──────────────────────────────────────────────

T["module"] = MiniTest.new_set()

T["module"]["has correct name"] = function()
  local name = child.lua_get([[mm.name]])
  MiniTest.expect.equality(name, "macos_media")
end

T["module"]["has a label"] = function()
  local label = child.lua_get([[mm.label]])
  MiniTest.expect.equality(label, "Now Playing")
end

T["module"]["exposes is_available function"] = function()
  local t = child.lua_get([[type(mm.is_available)]])
  MiniTest.expect.equality(t, "function")
end

T["module"]["exposes get_status function"] = function()
  local t = child.lua_get([[type(mm.get_status)]])
  MiniTest.expect.equality(t, "function")
end

T["module"]["exposes play_pause function"] = function()
  local t = child.lua_get([[type(mm.play_pause)]])
  MiniTest.expect.equality(t, "function")
end

T["module"]["exposes next_track function"] = function()
  local t = child.lua_get([[type(mm.next_track)]])
  MiniTest.expect.equality(t, "function")
end

T["module"]["exposes previous_track function"] = function()
  local t = child.lua_get([[type(mm.previous_track)]])
  MiniTest.expect.equality(t, "function")
end

T["module"]["exposes stop function"] = function()
  local t = child.lua_get([[type(mm.stop)]])
  MiniTest.expect.equality(t, "function")
end

T["module"]["exposes seek function"] = function()
  local t = child.lua_get([[type(mm.seek)]])
  MiniTest.expect.equality(t, "function")
end

T["module"]["exposes get_artwork function"] = function()
  local t = child.lua_get([[type(mm.get_artwork)]])
  MiniTest.expect.equality(t, "function")
end

-- ── parse_output ───────────────────────────────────────────────

T["parse_output"] = MiniTest.new_set()

T["parse_output"]["parses Spotify-style output correctly"] = function()
  -- nowplaying-cli outputs one value per line for each requested field
  -- Fields requested: title artist album duration elapsedTime playbackRate
  local result = child.lua_get([[
    (function()
      local lines = "Disarm - 2011 Remaster\nThe Smashing Pumpkins\nSiamese Dream\n261.48\n83.77\n1"
      return mm._parse_output(lines)
    end)()
  ]])
  MiniTest.expect.equality(result.track.title, "Disarm - 2011 Remaster")
  MiniTest.expect.equality(result.track.artist, "The Smashing Pumpkins")
  MiniTest.expect.equality(result.track.album, "Siamese Dream")
  MiniTest.expect.equality(result.track.duration, 261)
  MiniTest.expect.equality(result.position, 84)
  MiniTest.expect.equality(result.status, "playing")
end

T["parse_output"]["maps playbackRate 0 to paused"] = function()
  local result = child.lua_get([[
    (function()
      local lines = "Some Track\nSome Artist\nSome Album\n180\n45.2\n0"
      return mm._parse_output(lines)
    end)()
  ]])
  MiniTest.expect.equality(result.status, "paused")
end

T["parse_output"]["maps playbackRate 1 to playing"] = function()
  local result = child.lua_get([[
    (function()
      local lines = "Some Track\nSome Artist\nSome Album\n180\n45.2\n1"
      return mm._parse_output(lines)
    end)()
  ]])
  MiniTest.expect.equality(result.status, "playing")
end

T["parse_output"]["handles YouTube output with empty album"] = function()
  -- YouTube videos report empty string for album
  local result = child.lua_get([[
    (function()
      local lines = "OpenCode setup: Beginner's Crash course\nDarren Builds AI\n\n1107.43\n83.77\n1"
      return mm._parse_output(lines)
    end)()
  ]])
  MiniTest.expect.equality(result.track.title, "OpenCode setup: Beginner's Crash course")
  MiniTest.expect.equality(result.track.artist, "Darren Builds AI")
  MiniTest.expect.equality(result.track.album, "")
  MiniTest.expect.equality(result.track.duration, 1107)
  MiniTest.expect.equality(result.status, "playing")
end

T["parse_output"]["handles null/empty fields gracefully"] = function()
  -- When nothing is playing, nowplaying-cli returns "null" for fields
  local result = child.lua_get([[
    (function()
      local lines = "null\nnull\nnull\nnull\nnull\nnull"
      return mm._parse_output(lines)
    end)()
  ]])
  MiniTest.expect.equality(result.status, "inactive")
end

T["parse_output"]["returns inactive for completely empty output"] = function()
  local result = child.lua_get([[
    (function()
      return mm._parse_output("")
    end)()
  ]])
  MiniTest.expect.equality(result.status, "inactive")
end

T["parse_output"]["rounds duration and position to nearest integer"] = function()
  local result = child.lua_get([[
    (function()
      local lines = "Track\nArtist\nAlbum\n261.789\n83.234\n1"
      return mm._parse_output(lines)
    end)()
  ]])
  MiniTest.expect.equality(result.track.duration, 262)
  MiniTest.expect.equality(result.position, 83)
end

T["parse_output"]["handles fractional playbackRate as playing"] = function()
  -- Some apps report playbackRate as 1.0 or 2.0 for speed
  local result = child.lua_get([[
    (function()
      local lines = "Track\nArtist\nAlbum\n180\n45\n2"
      return mm._parse_output(lines)
    end)()
  ]])
  MiniTest.expect.equality(result.status, "playing")
end

-- ── is_available ───────────────────────────────────────────────

T["is_available"] = MiniTest.new_set()

T["is_available"]["returns false when nowplaying-cli not in PATH"] = function()
  -- In the child process, nowplaying-cli may or may not be installed,
  -- but we can test the function type is correct
  local result = child.lua_get([[
    (function()
      -- Temporarily override executable check
      local orig = vim.fn.executable
      vim.fn.executable = function() return 0 end
      local avail = mm.is_available()
      vim.fn.executable = orig
      return avail
    end)()
  ]])
  MiniTest.expect.equality(result, false)
end

T["is_available"]["returns true when nowplaying-cli is in PATH"] = function()
  local result = child.lua_get([[
    (function()
      local orig = vim.fn.executable
      vim.fn.executable = function() return 1 end
      local avail = mm.is_available()
      vim.fn.executable = orig
      return avail
    end)()
  ]])
  MiniTest.expect.equality(result, true)
end

-- ── format_provider integration ────────────────────────────────

T["format_provider"] = MiniTest.new_set()

T["format_provider"]["formats macos_media nicely"] = function()
  local label = child.lua_get([[
    require("player.utils").format_provider("macos_media")
  ]])
  MiniTest.expect.equality(label, "Now Playing")
end

return T
