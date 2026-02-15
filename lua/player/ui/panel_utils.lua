-- Pure utility functions extracted from panel.lua for testability.
local M = {}

--- Truncate text to fit within max_width display columns, appending "..." if needed.
function M.truncate_text(text, max_width)
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

--- Center text within a given width, padding with spaces.
function M.center_text(text, width)
  local text_width = vim.fn.strdisplaywidth(text)
  if text_width >= width then
    return text
  end
  local padding_left = math.floor((width - text_width) / 2)
  local padding_right = width - text_width - padding_left
  return string.rep(" ", padding_left) .. text .. string.rep(" ", padding_right)
end

--- Format seconds as "M:SS".
function M.format_time(seconds)
  if not seconds then
    return "?:??"
  end
  local s = math.floor(tonumber(seconds) or 0)
  local m = math.floor(s / 60)
  local rem = s % 60
  return string.format("%d:%02d", m, rem)
end

--- Build a progress bar string of the given width.
function M.progress_bar(position, duration, width)
  width = width or 28
  if not position or not duration or duration == 0 then
    return string.rep("░", width)
  end
  local ratio = math.min(math.max(position / duration, 0), 1)
  local filled = math.max(0, math.floor(width * ratio))
  return string.rep("█", filled) .. string.rep("░", width - filled)
end

--- Detect which zone of a window the mouse is in.
--- Used to decide between drag-to-move (body) and resize (edge/corner).
---@param rel_row number  0-indexed row relative to window top-left (including border)
---@param rel_col number  0-indexed col relative to window top-left (including border)
---@param total_width number  total window width including border
---@param total_height number  total window height including border
---@param grab_size number  how many cells from each edge count as resize zone
---@return string  one of "body", "top", "bottom", "left", "right",
---                "top_left", "top_right", "bottom_left", "bottom_right"
function M.detect_zone(rel_row, rel_col, total_width, total_height, grab_size)
  local near_top = rel_row < grab_size
  local near_bottom = rel_row >= total_height - grab_size
  local near_left = rel_col < grab_size
  local near_right = rel_col >= total_width - grab_size

  -- Corners (both axes in grab zone)
  if near_top and near_left then
    return "top_left"
  end
  if near_top and near_right then
    return "top_right"
  end
  if near_bottom and near_left then
    return "bottom_left"
  end
  if near_bottom and near_right then
    return "bottom_right"
  end

  -- Edges (single axis)
  if near_top then
    return "top"
  end
  if near_bottom then
    return "bottom"
  end
  if near_left then
    return "left"
  end
  if near_right then
    return "right"
  end

  return "body"
end

--- Clamp a width/height pair to min/max bounds.
---@param width number
---@param height number
---@param min_w number
---@param min_h number
---@param max_w number
---@param max_h number
---@return number[]  {clamped_width, clamped_height}
function M.clamp_size(width, height, min_w, min_h, max_w, max_h)
  local w = math.max(min_w, math.min(width, max_w))
  local h = math.max(min_h, math.min(height, max_h))
  return { w, h }
end

return M
