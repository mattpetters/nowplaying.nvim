local config = require("player.config")
local state = require("player.state")

local M = {}

local buf, win
local current_width, current_height
local current_image -- Track current image object for cleanup
local last_artwork_path -- Track the last artwork path to avoid re-rendering
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

  -- If artwork hasn't changed and image is still present, keep it to avoid flicker.
  if current_image and last_artwork_path == artwork_path and win and vim.api.nvim_win_is_valid(win) then
    return true
  end

  render_seq = render_seq + 1
  local expected_seq = render_seq

  -- Always clear the previous image before re-rendering to avoid duplicates
  if current_image then
    clear_current_image()
  end

  last_artwork_path = artwork_path

  -- Create new image with absolute geometry
  -- Need to defer until window position is stable
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
    -- Verify we're still showing the same artwork
    if last_artwork_path ~= artwork_path then
      return
    end

    if current_image then
      clear_current_image()
    end

    -- Create and render new image with inline mode
    -- For inline mode: x is column (0-based), y is line number (1-based) in the buffer
    -- The image should appear starting at line 2 (empty line after title)
    local panel_cfg = config.get().panel
    local panel_width = (vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_width(win)) or current_width or panel_cfg.width or 60
    local artwork_cfg = (panel_cfg.elements or {}).artwork or {}
    local img_width = artwork_cfg.width or 20
    local img_height = artwork_cfg.height or 10
    -- Miniplayer layout keeps artwork on the left.
    local x_offset = 2

    local img = image_nvim.from_file(artwork_path, {
      window = win,
      buffer = buf,
      inline = true,
      x = x_offset,
      y = 2,
      width = img_width,
      height = img_height,
    })

    if img then
      current_image = img
      img:render()

      -- Lock cursor position after image renders to prevent jumping
      vim.schedule(function()
        if win and vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_set_cursor(win, { 1, 0 })
        end
      end)
    end
  end, 90)

  return true
end

local function truncate_text(text, max_width)
  if not text then
    return ""
  end
  local width = vim.fn.strdisplaywidth(text)
  if width <= max_width then
    return text
  end
  if max_width <= 3 then
    return string.rep(".", max_width)
  end

  local target = max_width - 3
  local out = ""
  local chars = vim.fn.strchars(text)
  for i = 1, chars do
    local ch = vim.fn.strcharpart(text, i - 1, 1)
    if vim.fn.strdisplaywidth(out .. ch) > target then
      break
    end
    out = out .. ch
  end
  return out .. "..."
end

local function center_text(text, width)
  local text_width = vim.fn.strdisplaywidth(text)
  if text_width >= width then
    return text
  end
  local padding_left = math.floor((width - text_width) / 2)
  local padding_right = width - text_width - padding_left
  return string.rep(" ", padding_left) .. text .. string.rep(" ", padding_right)
end

local function format_time(seconds)
  if not seconds then
    return "?:??"
  end
  local s = math.floor(tonumber(seconds) or 0)
  local m = math.floor(s / 60)
  local rem = s % 60
  return string.format("%d:%02d", m, rem)
end

local function progress_bar(position, duration, width)
  width = width or 28
  if not position or not duration or duration == 0 then
    return string.rep("░", width)
  end
  local ratio = math.min(math.max(position / duration, 0), 1)
  local filled = math.max(0, math.floor(width * ratio))
  return string.rep("█", filled) .. string.rep("░", width - filled)
end

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
    height = height + 2 -- one spacer + bar row
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
  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  vim.api.nvim_buf_set_option(buf, "readonly", false)

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
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "readonly", true)
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
  vim.keymap.set("n", "<C-d>", noop, opts)
  vim.keymap.set("n", "<C-u>", noop, opts)
  vim.keymap.set("n", "<C-f>", noop, opts)
  vim.keymap.set("n", "<C-b>", noop, opts)
  vim.keymap.set("n", "<C-e>", noop, opts)
  vim.keymap.set("n", "<C-y>", noop, opts)
  vim.keymap.set("n", "j", noop, opts)
  vim.keymap.set("n", "k", noop, opts)
  vim.keymap.set("n", "gg", noop, opts)
  vim.keymap.set("n", "G", noop, opts)
  vim.keymap.set("n", "<Down>", noop, opts)
  vim.keymap.set("n", "<Up>", noop, opts)
  vim.keymap.set("n", "<PageDown>", noop, opts)
  vim.keymap.set("n", "<PageUp>", noop, opts)

  -- Disable mouse scrolling
  vim.keymap.set("n", "<ScrollWheelUp>", noop, opts)
  vim.keymap.set("n", "<ScrollWheelDown>", noop, opts)
  vim.keymap.set("n", "<ScrollWheelLeft>", noop, opts)
  vim.keymap.set("n", "<ScrollWheelRight>", noop, opts)
end

function M.open(state_snapshot)
  local opts = config.get().panel
  if not opts.enabled then
    return
  end

  local snapshot = state_snapshot or state.current

  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(buf, "bufhidden", "hide")
    vim.api.nvim_buf_set_option(buf, "filetype", "player_panel")
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
  })

  -- Disable scrolling in the window
  vim.api.nvim_win_set_option(win, "scrolloff", 0)
  vim.api.nvim_win_set_option(win, "cursorline", false)
  vim.api.nvim_win_set_option(win, "scroll", 0)
  vim.api.nvim_win_set_option(win, "winhl", "Normal:Normal,FloatBorder:FloatBorder")
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "readonly", true)

  ensure_keymaps()
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
  -- Clean up image
  if current_image then
    pcall(function()
      current_image:clear()
    end)
    current_image = nil
  end
  render_seq = render_seq + 1
  last_artwork_path = nil

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

return M
