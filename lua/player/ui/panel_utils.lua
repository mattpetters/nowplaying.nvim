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

return M
