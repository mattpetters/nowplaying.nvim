local config = require("player.config")
local state = require("player.state")
local panel_utils = require("player.ui.panel_utils")

local M = {}

local buf, win
local current_width, current_height
local drag_start_mouse = nil -- { row, col } of mouse when drag began
local drag_start_win = nil -- { row, col } of window when drag began
local current_image -- Track current image object for cleanup
local last_artwork_path -- Track the last artwork path to avoid re-rendering
local last_image_key -- Track render geometry to avoid stale image placement
local render_seq = 0 -- Monotonic token to discard stale deferred renders

local function clear_current_image()
  if current_image then
    pcall(function()
      current_image:clear()
    end)
    current_image = nil
  end
end

local function is_valid_window()
  return win and vim.api.nvim_win_is_valid(win)
end

function M.is_open()
  return is_valid_window()
end

local function try_render_image(artwork_path)
  -- Try to use image.nvim if available
  local ok, image_nvim = pcall(require, "image")
  if not ok or not image_nvim then
    return nil -- Fall back to ASCII
  end

  -- Verify file exists before trying to render
  local utils = require("player.utils")
  if not utils.file_exists(artwork_path) then
    return nil -- File doesn't exist yet, fall back to ASCII
  end

  local panel_cfg = config.get().panel
  local panel_width = (vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_width(win)) or current_width or panel_cfg.width or 60
  local artwork_cfg = (panel_cfg.elements or {}).artwork or {}
  local img_width = artwork_cfg.width or 20
  local img_height = artwork_cfg.height or 10
  local x_offset = 2
  local y_offset = 2
  local image_key = table.concat({
    tostring(artwork_path),
    tostring(win),
    tostring(panel_width),
    tostring(img_width),
    tostring(img_height),
    tostring(x_offset),
    tostring(y_offset),
  }, "|")

  -- If artwork and geometry are unchanged and image is still present, keep it to avoid flicker.
  if current_image and last_artwork_path == artwork_path and last_image_key == image_key and win and vim.api.nvim_win_is_valid(win) then
    return true
  end

  render_seq = render_seq + 1
  local expected_seq = render_seq

  -- Always clear the previous image before re-rendering to avoid duplicates
  if current_image then
    clear_current_image()
  end

  last_artwork_path = artwork_path
  last_image_key = image_key

  -- Create new image with absolute geometry and defer until float placement settles.
  vim.defer_fn(function()
    if expected_seq ~= render_seq then
      return
    end
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    if not win or not vim.api.nvim_win_is_valid(win) then
      return
    end
    if last_artwork_path ~= artwork_path or last_image_key ~= image_key then
      return
    end

    if current_image then
      clear_current_image()
    end

    local img = image_nvim.from_file(artwork_path, {
      window = win,
      buffer = buf,
      inline = false,
      x = x_offset,
      y = y_offset,
      width = img_width,
      height = img_height,
    })

    if img then
      current_image = img
      img:render()

      vim.schedule(function()
        if win and vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_set_cursor(win, { 1, 0 })
        end
      end)
    end
  end, 80)

  return true
end

-- Pure text helpers extracted to panel_utils for testability.
local truncate_text = panel_utils.truncate_text
local center_text = panel_utils.center_text
local format_time = panel_utils.format_time
local progress_bar = panel_utils.progress_bar

local function compute_content_height(state_snapshot)
  local panel_cfg = config.get().panel
  local elements = panel_cfg.elements or {}
  local artwork_cfg = elements.artwork or {}

  if not state_snapshot or state_snapshot.status == "inactive" then
    return 2
  end

  local art_h = artwork_cfg.enabled and (artwork_cfg.height or 6) or 4
  local meta_rows = 0
  if elements.track_title then
    meta_rows = meta_rows + 1
  end
  if elements.artist then
    meta_rows = meta_rows + 1
  end
  if elements.album then
    meta_rows = meta_rows + 1
  end
  meta_rows = math.max(meta_rows, 2)

  local height = 2 + math.max(art_h, meta_rows) -- header + spacer + content block
  if elements.progress_bar then
    height = height + 2 -- one spacer row + bar row
  end
  if elements.controls then
    height = height + 2
  end

  return math.max(height, 3)
end

local function resolve_dimensions(state_snapshot)
  local panel_cfg = config.get().panel
  local width = panel_cfg.width or 60
  width = math.max(20, math.min(width, vim.o.columns - 4))

  local height
  if panel_cfg.height then
    height = panel_cfg.height
  else
    height = compute_content_height(state_snapshot)
  end

  height = math.max(5, math.min(height, vim.o.lines - 4))
  return width, height
end

local function render(state_snapshot)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  -- Temporarily make buffer modifiable for updates
  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_set_option_value("readonly", false, { buf = buf })

  local lines = {}
  local panel_cfg = config.get().panel
  local panel_width = (is_valid_window() and vim.api.nvim_win_get_width(win)) or current_width or panel_cfg.width or 60
  local panel_elements = panel_cfg.elements or {}

  local function pad_or_truncate(text, width)
    local t = text or ""
    if width <= 0 then
      return ""
    end
    local t_width = vim.fn.strdisplaywidth(t)
    if t_width > width then
      return truncate_text(t, width)
    end
    return t .. string.rep(" ", width - t_width)
  end

  local function center_cell(text, width)
    local t = text or ""
    local t_width = vim.fn.strdisplaywidth(t)
    if t_width >= width then
      return t
    end
    local left = math.floor((width - t_width) / 2)
    local right = width - t_width - left
    return string.rep(" ", left) .. t .. string.rep(" ", right)
  end

  if not state_snapshot or state_snapshot.status == "inactive" then
    table.insert(lines, center_text("NowPlaying.nvim", panel_width))
    table.insert(lines, center_text("No active player", panel_width))
  else
    local track = state_snapshot.track or {}
    local status_icon = state_snapshot.status == "playing" and "▶" or "⏸"
    local title_line = string.format(
      "NowPlaying.nvim  │  Player: %s %s",
      state_snapshot.player_label or require("player.utils").format_provider(state_snapshot.player),
      status_icon
    )
    table.insert(lines, center_text(title_line, panel_width))

    local cfg = panel_elements.artwork or {}
    local art_w = cfg.enabled and (cfg.width or 10) or 0
    local art_h = cfg.enabled and (cfg.height or 6) or 4
    local left_pad = 2
    local gap = cfg.enabled and 2 or 0
    local right_w = math.max(panel_width - left_pad - art_w - gap - 2, 18)

    local meta_lines = {}
    if panel_elements.track_title then
      table.insert(meta_lines, truncate_text(track.title or "Unknown", right_w))
    end
    if panel_elements.artist then
      table.insert(meta_lines, truncate_text(track.artist or "Unknown", right_w))
    end
    if panel_elements.album then
      table.insert(meta_lines, truncate_text(track.album or "Unknown", right_w))
    end
    if #meta_lines == 0 then
      table.insert(meta_lines, "No track metadata")
    end

    local block_h = math.max(art_h, #meta_lines)
    local meta_start = math.max(1, math.floor((block_h - #meta_lines) / 2) + 1)

    for row_idx = 1, block_h do
      local right_text = ""
      if row_idx >= meta_start and row_idx < meta_start + #meta_lines then
        right_text = meta_lines[row_idx - meta_start + 1]
      end
      local line = string.rep(" ", left_pad) .. string.rep(" ", art_w) .. string.rep(" ", gap) .. pad_or_truncate(right_text, right_w)
      table.insert(lines, pad_or_truncate(line, panel_width))
    end

    if cfg.enabled and state_snapshot.artwork and state_snapshot.artwork.path then
      try_render_image(state_snapshot.artwork.path)
    else
      render_seq = render_seq + 1
      clear_current_image()
      last_artwork_path = nil
      last_image_key = nil
    end

    if panel_elements.progress_bar then
      table.insert(lines, string.rep(" ", panel_width))
      local pos = format_time(state_snapshot.position)
      local duration = tonumber(track.duration) or 0
      local elapsed = tonumber(state_snapshot.position) or 0
      local remaining = duration > 0 and math.max(duration - elapsed, 0) or nil
      local left_time = pos
      local right_time = remaining and ("-" .. format_time(remaining)) or "-?:??"
      local bar_w = math.max(panel_width - #left_time - #right_time - 6, 10)
      local progress_line = string.format("%s [%s] %s", left_time, progress_bar(state_snapshot.position, track.duration, bar_w), right_time)
      table.insert(lines, center_text(progress_line, panel_width))
    end

    if panel_elements.controls then
      local play_icon = state_snapshot.status == "playing" and "⏸" or "▶"
      local cell_w = 8
      local icon_row = center_cell("⏮", cell_w) .. center_cell(play_icon, cell_w) .. center_cell("⏹", cell_w) .. center_cell("⏭", cell_w)
      local key_row = center_cell("[b]", cell_w) .. center_cell("[p]", cell_w) .. center_cell("[x]", cell_w) .. center_cell("[n]", cell_w)
      table.insert(lines, center_text(icon_row, panel_width))
      table.insert(lines, center_text(key_row, panel_width))
    end
  end

  while #lines < current_height do
    table.insert(lines, string.rep(" ", panel_width))
  end
  while #lines > current_height do
    table.remove(lines)
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Lock cursor to top-left position
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_set_cursor(win, { 1, 0 })
  end

  -- Make buffer readonly again to prevent scrolling and editing
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  vim.api.nvim_set_option_value("readonly", true, { buf = buf })
end

local function ensure_keymaps()
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local opts = { silent = true, nowait = true, buffer = buf }

  -- Playback controls
  vim.keymap.set("n", "q", M.close, opts)
  vim.keymap.set("n", "p", function()
    state.play_pause()
  end, opts)
  vim.keymap.set("n", "n", function()
    state.next_track()
  end, opts)
  vim.keymap.set("n", "b", function()
    state.previous_track()
  end, opts)
  vim.keymap.set("n", "x", function()
    state.stop()
  end, opts)
  vim.keymap.set("n", "+", function()
    state.volume_up()
  end, opts)
  vim.keymap.set("n", "=", function()
    state.volume_up()
  end, opts)
  vim.keymap.set("n", "-", function()
    state.volume_down()
  end, opts)
  vim.keymap.set("n", "r", function()
    state.refresh()
  end, opts)
  vim.keymap.set("n", ">", function()
    local ok, err = state.seek(5)
    if not ok then
      vim.notify("Seek forward failed: " .. tostring(err), vim.log.levels.ERROR)
    end
  end, opts)
  vim.keymap.set("n", "<", function()
    local ok, err = state.seek(-5)
    if not ok then
      vim.notify("Seek backward failed: " .. tostring(err), vim.log.levels.ERROR)
    end
  end, opts)
  vim.keymap.set("n", "l", function()
    local ok, err = state.seek(5)
    if not ok then
      vim.notify("Seek forward failed: " .. tostring(err), vim.log.levels.ERROR)
    end
  end, opts)
  vim.keymap.set("n", "h", function()
    local ok, err = state.seek(-5)
    if not ok then
      vim.notify("Seek backward failed: " .. tostring(err), vim.log.levels.ERROR)
    end
  end, opts)

  -- Disable scrolling keys
  local noop = function() end
  local all_modes = { "n", "v", "x", "s", "i" }
  for _, mode in ipairs(all_modes) do
    vim.keymap.set(mode, "<C-d>", noop, opts)
    vim.keymap.set(mode, "<C-u>", noop, opts)
    vim.keymap.set(mode, "<C-f>", noop, opts)
    vim.keymap.set(mode, "<C-b>", noop, opts)
    vim.keymap.set(mode, "<C-e>", noop, opts)
    vim.keymap.set(mode, "<C-y>", noop, opts)
    vim.keymap.set(mode, "<Down>", noop, opts)
    vim.keymap.set(mode, "<Up>", noop, opts)
    vim.keymap.set(mode, "<PageDown>", noop, opts)
    vim.keymap.set(mode, "<PageUp>", noop, opts)
    vim.keymap.set(mode, "<ScrollWheelUp>", noop, opts)
    vim.keymap.set(mode, "<ScrollWheelDown>", noop, opts)
    vim.keymap.set(mode, "<ScrollWheelLeft>", noop, opts)
    vim.keymap.set(mode, "<ScrollWheelRight>", noop, opts)
  end
  vim.keymap.set("n", "j", noop, opts)
  vim.keymap.set("n", "k", noop, opts)
  vim.keymap.set("n", "gg", noop, opts)
  vim.keymap.set("n", "G", noop, opts)

  -- Mouse interaction: prevent cursor movement, text selection, and scrolling.
  --
  -- IMPORTANT: Mouse keys (<LeftMouse>, <LeftDrag>, <LeftRelease>) embed
  -- position data.  Neovim's built-in handling processes cursor repositioning
  -- *before* a Lua-callback mapping fires, so mapping to a function alone
  -- cannot prevent the cursor from jumping.
  --
  -- The solution: map these keys to <Nop> (string mapping, NOT a Lua function)
  -- which tells Neovim to completely discard the event including its built-in
  -- side effects.  For drag-to-move we use <Cmd> mappings which execute
  -- without mode changes and without triggering built-in mouse behaviour.

  local panel_cfg = config.get().panel
  local draggable = panel_cfg.draggable

  -- Block all mouse clicks, drags, and releases from doing anything by default.
  -- <Nop> as a string RHS prevents the built-in cursor-move/selection behaviour.
  for _, mode in ipairs({ "n", "v", "x", "s", "i" }) do
    vim.keymap.set(mode, "<LeftMouse>", "<Nop>", opts)
    vim.keymap.set(mode, "<2-LeftMouse>", "<Nop>", opts)
    vim.keymap.set(mode, "<3-LeftMouse>", "<Nop>", opts)
    vim.keymap.set(mode, "<4-LeftMouse>", "<Nop>", opts)
    vim.keymap.set(mode, "<RightMouse>", "<Nop>", opts)
    vim.keymap.set(mode, "<MiddleMouse>", "<Nop>", opts)

    if draggable then
      -- Use <Cmd> to run drag logic without triggering built-in mouse behaviour
      vim.keymap.set(mode, "<LeftDrag>", "<Cmd>lua require('player.ui.panel')._handle_drag()<CR>", opts)
      vim.keymap.set(mode, "<LeftRelease>", "<Cmd>lua require('player.ui.panel')._handle_release()<CR>", opts)
    else
      vim.keymap.set(mode, "<LeftDrag>", "<Nop>", opts)
      vim.keymap.set(mode, "<LeftRelease>", "<Nop>", opts)
    end
  end
end

function M.open(state_snapshot)
  local opts = config.get().panel
  if not opts.enabled then
    return
  end

  local snapshot = state_snapshot or state.current

  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("bufhidden", "hide", { buf = buf })
    vim.api.nvim_set_option_value("filetype", "player_panel", { buf = buf })
  end

  local width, height = resolve_dimensions(snapshot)
  current_width = width
  current_height = height
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = opts.border,
    mouse = true,
  })

  -- Options not already covered by style="minimal"
  local wo = function(name, value)
    vim.api.nvim_set_option_value(name, value, { win = win })
  end
  wo("scrolloff", 0)
  wo("sidescrolloff", 0)
  wo("wrap", false)
  wo("winbar", "")
  wo("winhighlight", "Normal:Normal,FloatBorder:FloatBorder")
  wo("winblend", 0)

  local bo = function(name, value)
    vim.api.nvim_set_option_value(name, value, { buf = buf })
  end
  bo("modifiable", false)
  bo("readonly", true)

  ensure_keymaps()

  -- Prevent the buffer from ever scrolling by pinning cursor to {1,0}.
  -- CursorMoved fires *before* the screen redraws, so this stops scroll
  -- at the source rather than reactively snapping back after the fact.
  -- This also prevents album art (rendered at absolute window position)
  -- from escaping the panel bounds when the text layer shifts.
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = buf,
    callback = function()
      if not is_valid_window() then
        return true -- remove autocmd when window is gone
      end
      local cursor = vim.api.nvim_win_get_cursor(win)
      if cursor[1] ~= 1 or cursor[2] ~= 0 then
        vim.api.nvim_win_set_cursor(win, { 1, 0 })
      end
    end,
  })

  -- Belt-and-suspenders: if something still manages to scroll the view
  -- (e.g. external command, WinResized side-effect), snap topline back.
  vim.api.nvim_create_autocmd("WinScrolled", {
    buffer = buf,
    callback = function()
      if not is_valid_window() then
        return true
      end
      local info = vim.fn.getwininfo(win)
      if info and info[1] and info[1].topline ~= 1 then
        vim.api.nvim_win_call(win, function()
          vim.fn.winrestview({ topline = 1, lnum = 1, col = 0 })
        end)
        -- Force artwork re-render since position was stale
        if current_image then
          render_seq = render_seq + 1
          clear_current_image()
          last_image_key = nil
          local s = state.current
          if s and s.artwork and s.artwork.path then
            try_render_image(s.artwork.path)
          end
        end
      end
    end,
  })

  render(snapshot)
end

function M.update(state_snapshot)
  if not is_valid_window() then
    return
  end

  local snapshot = state_snapshot or state.current
  local panel_cfg = config.get().panel
  if not panel_cfg.height then
    local _, new_height = resolve_dimensions(snapshot)
    if new_height ~= current_height then
      vim.api.nvim_win_set_height(win, new_height)
      current_height = new_height
    end
  end

  render(snapshot)
end

function M.close()
  clear_current_image()
  render_seq = render_seq + 1
  last_artwork_path = nil
  last_image_key = nil

  if is_valid_window() then
    vim.api.nvim_win_close(win, true)
  end
  win = nil
  current_width = nil
  current_height = nil
end

function M.toggle(state_snapshot)
  if is_valid_window() then
    M.close()
  else
    M.open(state_snapshot)
  end
end

-- Internal drag-to-move handlers, exposed on the module table so that
-- <Cmd>lua require('player.ui.panel')._handle_drag()<CR> works from a
-- string keymap (which is required to fully suppress built-in mouse events).

function M._handle_drag()
  if not is_valid_window() then
    return
  end
  local mouse = vim.fn.getmousepos()
  if not drag_start_mouse then
    -- First drag event: capture starting positions
    local win_cfg = vim.api.nvim_win_get_config(win)
    drag_start_mouse = { row = mouse.screenrow, col = mouse.screencol }
    drag_start_win = { row = win_cfg.row, col = win_cfg.col }
    return
  end
  local dy = mouse.screenrow - drag_start_mouse.row
  local dx = mouse.screencol - drag_start_mouse.col
  local new_row = math.max(0, drag_start_win.row + dy)
  local new_col = math.max(0, drag_start_win.col + dx)
  vim.api.nvim_win_set_config(win, {
    relative = "editor",
    row = new_row,
    col = new_col,
  })
  -- Re-render image after move so artwork tracks the window
  if current_image then
    render_seq = render_seq + 1
    clear_current_image()
    last_image_key = nil
    local snapshot = state.current
    if snapshot and snapshot.artwork and snapshot.artwork.path then
      try_render_image(snapshot.artwork.path)
    end
  end
end

function M._handle_release()
  drag_start_mouse = nil
  drag_start_win = nil
  -- Pin cursor back to top-left
  if is_valid_window() then
    vim.api.nvim_win_set_cursor(win, { 1, 0 })
  end
end

return M
