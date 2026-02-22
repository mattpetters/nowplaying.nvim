-- Functional tests for the player panel floating window
-- Tests window lifecycle, properties, scroll prevention, mouse behavior,
-- and keymaps through a child Neovim process.
local H = dofile("tests/helpers.lua")

local T = MiniTest.new_set({
  hooks = {
    pre_once = function()
      _G.child = H.new_child()
    end,
    post_once = function()
      child.stop()
    end,
    -- Clean slate before each test: close any panel, reset modules
    pre_case = function()
      child.lua([[
        package.loaded["player.config"] = nil
        package.loaded["player.state"] = nil
        package.loaded["player.ui.panel"] = nil
        package.loaded["player.ui.panel_utils"] = nil
        -- Close any lingering floats
        for _, w in ipairs(vim.api.nvim_list_wins()) do
          local cfg = vim.api.nvim_win_get_config(w)
          if cfg.relative and cfg.relative ~= "" then
            pcall(vim.api.nvim_win_close, w, true)
          end
        end
      ]])
      H.setup_plugin(child)
    end,
  },
})

-- ── helpers ────────────────────────────────────────────────────

--- Open the panel in the child and return its window id
local function open_panel()
  H.open_panel(child)
  return H.get_panel_win(child)
end

--- Count floating windows in the child
local function float_count()
  return child.lua_get([[
    (function()
      local n = 0
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        local c = vim.api.nvim_win_get_config(w)
        if c.relative and c.relative ~= "" then n = n + 1 end
      end
      return n
    end)()
  ]])
end

-- ══════════════════════════════════════════════════════════════
-- Lifecycle
-- ══════════════════════════════════════════════════════════════

T["lifecycle"] = MiniTest.new_set()

T["lifecycle"]["open creates a floating window"] = function()
  open_panel()
  MiniTest.expect.equality(float_count(), 1)
end

T["lifecycle"]["close removes the floating window"] = function()
  open_panel()
  child.lua([[require("player.ui.panel").close()]])
  MiniTest.expect.equality(float_count(), 0)
end

T["lifecycle"]["toggle opens then closes"] = function()
  child.lua([[
    local panel = require("player.ui.panel")
    panel.toggle()
  ]])
  MiniTest.expect.equality(float_count(), 1)

  child.lua([[require("player.ui.panel").toggle()]])
  MiniTest.expect.equality(float_count(), 0)
end

T["lifecycle"]["open does nothing when panel disabled"] = function()
  child.lua([[
    package.loaded["player.config"] = nil
    require("player.config").setup({ panel = { enabled = false } })
  ]])
  child.lua([[require("player.ui.panel").open()]])
  MiniTest.expect.equality(float_count(), 0)
end

T["lifecycle"]["is_open reflects state"] = function()
  local before = child.lua_get([[require("player.ui.panel").is_open()]])
  -- is_open() returns nil when closed; child translates nil to vim.NIL
  MiniTest.expect.equality(before == false or before == vim.NIL, true)

  open_panel()
  local after = child.lua_get([[require("player.ui.panel").is_open()]])
  MiniTest.expect.equality(after, true)
end

-- ══════════════════════════════════════════════════════════════
-- Window configuration (nvim_open_win properties)
-- ══════════════════════════════════════════════════════════════

T["window_config"] = MiniTest.new_set()

T["window_config"]["float is relative to editor"] = function()
  local win_id = open_panel()
  local rel = child.lua_get(
    string.format([[vim.api.nvim_win_get_config(%d).relative]], win_id)
  )
  MiniTest.expect.equality(rel, "editor")
end

T["window_config"]["mouse is enabled on the float"] = function()
  local win_id = open_panel()
  local mouse = child.lua_get(
    string.format([[vim.api.nvim_win_get_config(%d).mouse]], win_id)
  )
  MiniTest.expect.equality(mouse, true)
end

T["window_config"]["style is minimal"] = function()
  local win_id = open_panel()
  -- style='minimal' isn't returned in get_config, but its effects are visible:
  -- number, relativenumber, cursorline, cursorcolumn, spell, list, signcolumn, foldcolumn are off
  local number = child.lua_get(
    string.format([[vim.api.nvim_get_option_value("number", { win = %d })]], win_id)
  )
  local cursorline = child.lua_get(
    string.format([[vim.api.nvim_get_option_value("cursorline", { win = %d })]], win_id)
  )
  local spell = child.lua_get(
    string.format([[vim.api.nvim_get_option_value("spell", { win = %d })]], win_id)
  )
  MiniTest.expect.equality(number, false)
  MiniTest.expect.equality(cursorline, false)
  MiniTest.expect.equality(spell, false)
end

T["window_config"]["uses configured border"] = function()
  local win_id = open_panel()
  local border = child.lua_get(
    string.format([[vim.api.nvim_win_get_config(%d).border]], win_id)
  )
  -- "rounded" expands to a table of border characters
  MiniTest.expect.equality(type(border), "table")
end

-- ══════════════════════════════════════════════════════════════
-- Window options
-- ══════════════════════════════════════════════════════════════

T["window_options"] = MiniTest.new_set()

T["window_options"]["scrolloff is 0"] = function()
  local win_id = open_panel()
  local so = child.lua_get(
    string.format([[vim.api.nvim_get_option_value("scrolloff", { win = %d })]], win_id)
  )
  MiniTest.expect.equality(so, 0)
end

T["window_options"]["wrap is disabled"] = function()
  local win_id = open_panel()
  local wrap = child.lua_get(
    string.format([[vim.api.nvim_get_option_value("wrap", { win = %d })]], win_id)
  )
  MiniTest.expect.equality(wrap, false)
end

T["window_options"]["sidescrolloff is 0"] = function()
  local win_id = open_panel()
  local siso = child.lua_get(
    string.format([[vim.api.nvim_get_option_value("sidescrolloff", { win = %d })]], win_id)
  )
  MiniTest.expect.equality(siso, 0)
end

-- ══════════════════════════════════════════════════════════════
-- Buffer options
-- ══════════════════════════════════════════════════════════════

T["buffer_options"] = MiniTest.new_set()

T["buffer_options"]["buffer is not modifiable"] = function()
  open_panel()
  local modifiable = child.lua_get([[
    (function()
      local panel = require("player.ui.panel")
      -- Get buffer through win
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        local c = vim.api.nvim_win_get_config(w)
        if c.relative and c.relative ~= "" then
          local b = vim.api.nvim_win_get_buf(w)
          return vim.api.nvim_get_option_value("modifiable", { buf = b })
        end
      end
      return nil
    end)()
  ]])
  MiniTest.expect.equality(modifiable, false)
end

T["buffer_options"]["buffer is readonly"] = function()
  open_panel()
  local readonly = child.lua_get([[
    (function()
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        local c = vim.api.nvim_win_get_config(w)
        if c.relative and c.relative ~= "" then
          local b = vim.api.nvim_win_get_buf(w)
          return vim.api.nvim_get_option_value("readonly", { buf = b })
        end
      end
      return nil
    end)()
  ]])
  MiniTest.expect.equality(readonly, true)
end

T["buffer_options"]["filetype is player_panel"] = function()
  open_panel()
  local ft = child.lua_get([[
    (function()
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        local c = vim.api.nvim_win_get_config(w)
        if c.relative and c.relative ~= "" then
          local b = vim.api.nvim_win_get_buf(w)
          return vim.api.nvim_get_option_value("filetype", { buf = b })
        end
      end
      return nil
    end)()
  ]])
  MiniTest.expect.equality(ft, "player_panel")
end

-- ══════════════════════════════════════════════════════════════
-- Scroll prevention
-- ══════════════════════════════════════════════════════════════

T["scroll_prevention"] = MiniTest.new_set()

T["scroll_prevention"]["cursor is locked at line 1 col 0"] = function()
  local win_id = open_panel()
  local cursor = child.lua_get(
    string.format([[vim.api.nvim_win_get_cursor(%d)]], win_id)
  )
  MiniTest.expect.equality(cursor, { 1, 0 })
end

T["scroll_prevention"]["cursor snaps back after attempted movement"] = function()
  local win_id = open_panel()
  -- Try to move cursor to a different line via API
  child.lua(string.format([[
    pcall(function()
      vim.api.nvim_set_option_value("modifiable", true, { buf = vim.api.nvim_win_get_buf(%d) })
      vim.api.nvim_set_option_value("readonly", false, { buf = vim.api.nvim_win_get_buf(%d) })
    end)
  ]], win_id, win_id))

  -- Force focus to the panel window, set cursor to line 3
  child.lua(string.format([[
    vim.api.nvim_set_current_win(%d)
    pcall(vim.api.nvim_win_set_cursor, %d, { 3, 0 })
  ]], win_id, win_id))

  -- CursorMoved autocmd should fire and snap cursor back
  -- Give Neovim a chance to process the autocmd
  vim.loop.sleep(50)

  local cursor = child.lua_get(
    string.format([[vim.api.nvim_win_get_cursor(%d)]], win_id)
  )
  MiniTest.expect.equality(cursor, { 1, 0 })
end

T["scroll_prevention"]["topline stays at 1"] = function()
  local win_id = open_panel()
  local topline = child.lua_get(string.format([[
    (function()
      local info = vim.fn.getwininfo(%d)
      return info and info[1] and info[1].topline
    end)()
  ]], win_id))
  MiniTest.expect.equality(topline, 1)
end

-- ══════════════════════════════════════════════════════════════
-- Keymaps
-- ══════════════════════════════════════════════════════════════

T["keymaps"] = MiniTest.new_set()

T["keymaps"]["scroll wheel is disabled in normal mode"] = function()
  local win_id = open_panel()
  -- Focus panel window
  child.lua(string.format([[vim.api.nvim_set_current_win(%d)]], win_id))

  -- Get the mapping for <ScrollWheelDown> in normal mode
  local mapped = child.lua_get([[
    (function()
      local maps = vim.api.nvim_buf_get_keymap(0, "n")
      for _, m in ipairs(maps) do
        if m.lhs:find("ScrollWheelDown") then
          return true
        end
      end
      return false
    end)()
  ]])
  MiniTest.expect.equality(mapped, true)
end

T["keymaps"]["scroll wheel is disabled in visual mode"] = function()
  local win_id = open_panel()
  child.lua(string.format([[vim.api.nvim_set_current_win(%d)]], win_id))

  local mapped = child.lua_get([[
    (function()
      local maps = vim.api.nvim_buf_get_keymap(0, "v")
      for _, m in ipairs(maps) do
        if m.lhs:find("ScrollWheelDown") then
          return true
        end
      end
      return false
    end)()
  ]])
  MiniTest.expect.equality(mapped, true)
end

T["keymaps"]["LeftMouse is mapped in normal mode"] = function()
  local win_id = open_panel()
  child.lua(string.format([[vim.api.nvim_set_current_win(%d)]], win_id))

  local mapped = child.lua_get([[
    (function()
      local maps = vim.api.nvim_buf_get_keymap(0, "n")
      for _, m in ipairs(maps) do
        if m.lhs:find("LeftMouse") and not m.lhs:find("Drag") and not m.lhs:find("Release") then
          return true
        end
      end
      return false
    end)()
  ]])
  MiniTest.expect.equality(mapped, true)
end

T["keymaps"]["LeftDrag is mapped in visual mode"] = function()
  local win_id = open_panel()
  child.lua(string.format([[vim.api.nvim_set_current_win(%d)]], win_id))

  local mapped = child.lua_get([[
    (function()
      local maps = vim.api.nvim_buf_get_keymap(0, "v")
      for _, m in ipairs(maps) do
        if m.lhs:find("LeftDrag") then
          return true
        end
      end
      return false
    end)()
  ]])
  MiniTest.expect.equality(mapped, true)
end

T["keymaps"]["LeftRelease is mapped in select mode"] = function()
  local win_id = open_panel()
  child.lua(string.format([[vim.api.nvim_set_current_win(%d)]], win_id))

  local mapped = child.lua_get([[
    (function()
      local maps = vim.api.nvim_buf_get_keymap(0, "s")
      for _, m in ipairs(maps) do
        if m.lhs:find("LeftRelease") then
          return true
        end
      end
      return false
    end)()
  ]])
  MiniTest.expect.equality(mapped, true)
end

T["keymaps"]["playback controls are mapped (q, p, n, b, x)"] = function()
  local win_id = open_panel()
  child.lua(string.format([[vim.api.nvim_set_current_win(%d)]], win_id))

  local keys = child.lua_get([[
    (function()
      local result = {}
      local maps = vim.api.nvim_buf_get_keymap(0, "n")
      for _, m in ipairs(maps) do
        result[m.lhs] = true
      end
      return result
    end)()
  ]])
  MiniTest.expect.equality(keys["q"], true)
  MiniTest.expect.equality(keys["p"], true)
  MiniTest.expect.equality(keys["n"], true)
  MiniTest.expect.equality(keys["b"], true)
  MiniTest.expect.equality(keys["x"], true)
end

T["keymaps"]["j/k/gg/G are blocked in normal mode"] = function()
  local win_id = open_panel()
  child.lua(string.format([[vim.api.nvim_set_current_win(%d)]], win_id))

  local keys = child.lua_get([[
    (function()
      local result = {}
      local maps = vim.api.nvim_buf_get_keymap(0, "n")
      for _, m in ipairs(maps) do
        result[m.lhs] = true
      end
      return result
    end)()
  ]])
  MiniTest.expect.equality(keys["j"], true)
  MiniTest.expect.equality(keys["k"], true)
  MiniTest.expect.equality(keys["gg"], true)
  MiniTest.expect.equality(keys["G"], true)
end

-- ══════════════════════════════════════════════════════════════
-- Rendering
-- ══════════════════════════════════════════════════════════════

T["rendering"] = MiniTest.new_set()

T["rendering"]["inactive state shows no active player"] = function()
  -- Open panel with inactive state (no track playing)
  child.lua([[
    require("player.state").current = { status = "inactive" }
    require("player.ui.panel").open()
  ]])
  local lines = child.lua_get([[
    (function()
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        local c = vim.api.nvim_win_get_config(w)
        if c.relative and c.relative ~= "" then
          local b = vim.api.nvim_win_get_buf(w)
          return vim.api.nvim_buf_get_lines(b, 0, -1, false)
        end
      end
      return {}
    end)()
  ]])
  -- Should contain "No active player" somewhere in the buffer
  local found = false
  for _, line in ipairs(lines) do
    if line:find("No active player") then
      found = true
      break
    end
  end
  MiniTest.expect.equality(found, true)
end

T["rendering"]["active state shows track info"] = function()
  H.set_state(child, H.make_state({
    status = "playing",
    track = { title = "TestSong", artist = "TestArtist", album = "TestAlbum", duration = 200 },
    position = 50,
  }))
  child.lua([[
    package.loaded["player.ui.panel"] = nil
    require("player.ui.panel").open()
  ]])

  local lines = child.lua_get([[
    (function()
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        local c = vim.api.nvim_win_get_config(w)
        if c.relative and c.relative ~= "" then
          local b = vim.api.nvim_win_get_buf(w)
          return vim.api.nvim_buf_get_lines(b, 0, -1, false)
        end
      end
      return {}
    end)()
  ]])
  local text = table.concat(lines, "\n")
  MiniTest.expect.equality(text:find("TestSong") ~= nil, true)
  MiniTest.expect.equality(text:find("TestArtist") ~= nil, true)
end

T["rendering"]["update changes buffer content"] = function()
  open_panel()

  -- First check inactive
  local lines_before = child.lua_get([[
    (function()
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        local c = vim.api.nvim_win_get_config(w)
        if c.relative and c.relative ~= "" then
          local b = vim.api.nvim_win_get_buf(w)
          return vim.api.nvim_buf_get_lines(b, 0, 2, false)
        end
      end
      return {}
    end)()
  ]])

  -- Update with active state
  H.set_state(child, H.make_state({
    status = "playing",
    track = { title = "UpdatedTrack", artist = "UpdatedArtist", album = "A", duration = 100 },
    position = 30,
  }))
  child.lua([[require("player.ui.panel").update()]])

  local lines_after = child.lua_get([[
    (function()
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        local c = vim.api.nvim_win_get_config(w)
        if c.relative and c.relative ~= "" then
          local b = vim.api.nvim_win_get_buf(w)
          return vim.api.nvim_buf_get_lines(b, 0, -1, false)
        end
      end
      return {}
    end)()
  ]])
  local text = table.concat(lines_after, "\n")
  MiniTest.expect.equality(text:find("UpdatedTrack") ~= nil, true)
end

-- ══════════════════════════════════════════════════════════════
-- Code quality: no deprecated APIs
-- ══════════════════════════════════════════════════════════════

T["code_quality"] = MiniTest.new_set()

T["code_quality"]["panel.lua has no deprecated option calls"] = function()
  -- Read the panel source file and check for deprecated patterns
  local has_deprecated = child.lua_get([[
    (function()
      local path = vim.api.nvim_get_runtime_file("lua/player/ui/panel.lua", false)[1]
      if not path then return "file_not_found" end
      local f = io.open(path, "r")
      if not f then return "cannot_open" end
      local content = f:read("*a")
      f:close()
      local patterns = {
        "nvim_win_set_option",
        "nvim_buf_set_option",
        "nvim_win_get_option",
        "nvim_buf_get_option",
      }
      for _, pat in ipairs(patterns) do
        if content:find(pat, 1, true) then
          return pat
        end
      end
      return false
    end)()
  ]])
  MiniTest.expect.equality(has_deprecated, false)
end

-- ════════════════════════════════════════════════════════════════════════════
-- Responsive layout / redraw / resize behavior (TDD)
--
-- NOTE: These tests are intentionally written ahead of the panel refactor to
-- use the new responsive layout helpers in player.ui.panel_utils. They should
-- NOT error, but some assertions may fail until panel rendering is updated.
-- ════════════════════════════════════════════════════════════════════════════

local function resize_panel_win(win_id, new_width, new_height)
  child.lua(string.format(
    [[
      local win = %d
      local cfg = vim.api.nvim_win_get_config(win)
      vim.api.nvim_win_set_config(win, {
        relative = "editor",
        width = %d,
        height = %d,
        row = cfg.row,
        col = cfg.col,
      })
    ]],
    win_id,
    new_width,
    new_height
  ))
end

local function get_panel_text(win_id)
  local lines = child.lua_get(string.format(
    [[
      (function()
        local b = vim.api.nvim_win_get_buf(%d)
        return vim.api.nvim_buf_get_lines(b, 0, -1, false)
      end)()
    ]],
    win_id
  ))
  return table.concat(lines, "\n")
end

-- ════════════════════════════════════════════════════════════════════════════
-- responsive_layout
-- ════════════════════════════════════════════════════════════════════════════

T["responsive_layout"] = MiniTest.new_set()

T["responsive_layout"]["large panel shows controls and album"] = function()
  local snapshot = H.make_state({
    status = "playing",
    track = {
      title = "BigTrack",
      artist = "BigArtist",
      album = "BigAlbum",
      duration = 200,
    },
    position = 50,
  })

  local win_id = open_panel()
  -- Ensure the panel is rendering the intended state
  H.set_state(child, snapshot)

  resize_panel_win(win_id, 60, 16) -- large breakpoint
  child.lua([[require("player.ui.panel").update()]])

  local text = get_panel_text(win_id)
  local has_controls = (text:find("⏮", 1, true) ~= nil) or (text:find("⏭", 1, true) ~= nil)
  MiniTest.expect.equality(has_controls, true)
  MiniTest.expect.equality(text:find("BigAlbum", 1, true) ~= nil, true)
end

T["responsive_layout"]["small panel hides controls"] = function()
  local snapshot = H.make_state({
    status = "playing",
    track = {
      title = "SmallTrack",
      artist = "SmallArtist",
      album = "SmallAlbum",
      duration = 200,
    },
    position = 50,
  })

  local win_id = open_panel()
  H.set_state(child, snapshot)

  resize_panel_win(win_id, 32, 9) -- small breakpoint
  child.lua([[require("player.ui.panel").update()]])

  local text = get_panel_text(win_id)
  MiniTest.expect.equality(text:find("⏮", 1, true) == nil, true)
  MiniTest.expect.equality(text:find("SmallTrack", 1, true) ~= nil, true)
end

T["responsive_layout"]["tiny panel shows only title and artist"] = function()
  local snapshot = H.make_state({
    status = "playing",
    track = {
      title = "TinyTrack",
      artist = "TinyArtist",
      album = "TinyAlbum",
      duration = 200,
    },
    position = 50,
  })

  local win_id = open_panel()
  H.set_state(child, snapshot)

  resize_panel_win(win_id, 25, 6) -- tiny breakpoint
  child.lua([[require("player.ui.panel").update()]])

  local text = get_panel_text(win_id)
  MiniTest.expect.equality(text:find("TinyTrack", 1, true) ~= nil, true)
  MiniTest.expect.equality(text:find("TinyArtist", 1, true) ~= nil, true)
  MiniTest.expect.equality(text:find("TinyAlbum", 1, true) == nil, true)
  MiniTest.expect.equality(text:find("█", 1, true) == nil, true)
  MiniTest.expect.equality(text:find("░", 1, true) == nil, true)
end

T["responsive_layout"]["medium panel hides key hints but shows control icons"] = function()
  local snapshot = H.make_state({
    status = "playing",
    track = {
      title = "MedTrack",
      artist = "MedArtist",
      album = "MedAlbum",
      duration = 200,
    },
    position = 50,
  })

  local win_id = open_panel()
  H.set_state(child, snapshot)

  resize_panel_win(win_id, 45, 12) -- medium breakpoint
  child.lua([[require("player.ui.panel").update()]])

  local text = get_panel_text(win_id)
  MiniTest.expect.equality(text:find("⏮", 1, true) ~= nil, true)
  MiniTest.expect.equality(text:find("[b]", 1, true) == nil, true)
  MiniTest.expect.equality(text:find("[p]", 1, true) == nil, true)
end

-- ════════════════════════════════════════════════════════════════════════════
-- force_redraw
-- ════════════════════════════════════════════════════════════════════════════

T["force_redraw"] = MiniTest.new_set()

T["force_redraw"]["force_redraw re-renders with fresh state"] = function()
  -- Open panel with inactive state
  child.lua([[
    require("player.state").current = { status = "inactive" }
    require("player.ui.panel").open()
  ]])
  local win_id = H.get_panel_win(child)

  -- Set state to playing and force redraw
  H.set_state(child, H.make_state({
    status = "playing",
    track = { title = "FreshTrack", artist = "FreshArtist", album = "FreshAlbum", duration = 200 },
    position = 10,
  }))

  local ok = child.lua_get([[
    (function()
      local panel = require("player.ui.panel")
      if type(panel.force_redraw) ~= "function" then return false end
      return pcall(panel.force_redraw)
    end)()
  ]])
  MiniTest.expect.equality(ok, true)

  local text = get_panel_text(win_id)
  MiniTest.expect.equality(text:find("FreshTrack", 1, true) ~= nil, true)
end

T["force_redraw"]["force_redraw does nothing when panel is closed"] = function()
  -- Ensure panel is closed
  child.lua([[pcall(function() require("player.ui.panel").close() end)]])

  local ok = child.lua_get([[
    (function()
      local panel = require("player.ui.panel")
      if type(panel.force_redraw) ~= "function" then return false end
      return pcall(panel.force_redraw)
    end)()
  ]])
  MiniTest.expect.equality(ok, true)
  MiniTest.expect.equality(float_count(), 0)
end

-- ════════════════════════════════════════════════════════════════════════════
-- resize_behavior
-- ════════════════════════════════════════════════════════════════════════════

T["resize_behavior"] = MiniTest.new_set()

T["resize_behavior"]["panel respects min_width during resize"] = function()
  local win_id = open_panel()
  -- Try to resize window to something unrealistically small
  resize_panel_win(win_id, 10, 8)

  local ok = child.lua_get([[
    (function()
      local panel = require("player.ui.panel")
      return pcall(panel.update)
    end)()
  ]])
  -- Should remain functional (no errors); may still fail assertions elsewhere.
  MiniTest.expect.equality(ok, true)
  MiniTest.expect.equality(float_count(), 1)
end

T["resize_behavior"]["update adjusts height when content changes"] = function()
  -- Open with inactive state (minimal content)
  child.lua([[
    require("player.state").current = { status = "inactive" }
    require("player.ui.panel").open()
  ]])
  local win_id = H.get_panel_win(child)

  local h_before = child.lua_get(string.format([[vim.api.nvim_win_get_config(%d).height]], win_id))

  -- Update with active/playing state which should require more lines
  H.set_state(child, H.make_state({
    status = "playing",
    track = { title = "TallTrack", artist = "TallArtist", album = "TallAlbum", duration = 200 },
    position = 50,
  }))
  child.lua([[require("player.ui.panel").update()]])

  local h_after = child.lua_get(string.format([[vim.api.nvim_win_get_config(%d).height]], win_id))
  MiniTest.expect.equality(h_after > h_before, true)
end

-- ════════════════════════════════════════════════════════════════════════════
-- drag_artwork: artwork should move fluidly with the panel during drag
-- ════════════════════════════════════════════════════════════════════════════

T["drag_artwork"] = MiniTest.new_set()

T["drag_artwork"]["image is re-rendered during drag (not only on release)"] = function()
  -- The panel drag handler should schedule image re-renders during drag
  -- events rather than only clearing at drag start and re-rendering on release.
  -- Verify the source code pattern: _handle_drag should call a reposition function.
  local has_drag_render = child.lua_get([[
    (function()
      local path = vim.api.nvim_get_runtime_file("lua/player/ui/panel.lua", false)[1]
      if not path then return false end
      local f = io.open(path, "r")
      if not f then return false end
      local content = f:read("*a")
      f:close()
      -- The drag handler should schedule a throttled image reposition
      return content:find("reposition_image_throttled") ~= nil
    end)()
  ]])
  MiniTest.expect.equality(has_drag_render, true)
end

-- ════════════════════════════════════════════════════════════════════════════
-- panel_bg: background tint should be very subtle
-- ════════════════════════════════════════════════════════════════════════════

T["panel_bg"] = MiniTest.new_set()

T["panel_bg"]["apply_accent uses dark subtle background formula"] = function()
  -- Verify the panel's colors module uses darken (not lighten) for BG
  local has_dark_bg = child.lua_get([[
    (function()
      local path = vim.api.nvim_get_runtime_file("lua/player/ui/colors.lua", false)[1]
      if not path then return false end
      local f = io.open(path, "r")
      if not f then return false end
      local content = f:read("*a")
      f:close()
      -- The bg_hex line should use darken, not lighten
      local bg_line = content:match("bg_hex%s*=%s*[^\n]+")
      if not bg_line then return false end
      return bg_line:find("darken") ~= nil
    end)()
  ]])
  MiniTest.expect.equality(has_dark_bg, true)
end

return T
