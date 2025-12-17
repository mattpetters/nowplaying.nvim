local config = require("player.config")
local state = require("player.state")
local utils = require("player.utils")

local M = {}

local function format_icon(status)
  if status == "playing" then
    return "▶"
  elseif status == "paused" then
    return "⏸"
  end
  return "■"
end

local function truncate(text, max_length)
  if not max_length or max_length <= 0 then
    return text
  end
  local width = vim.fn.strdisplaywidth(text)
  if width <= max_length then
    return text
  end

  local ellipsis = "..."
  local target = max_length - #ellipsis
  if target <= 0 then
    return ellipsis:sub(1, max_length)
  end

  local truncated = text
  while vim.fn.strdisplaywidth(truncated) > target do
    local chars = vim.fn.strchars(truncated)
    truncated = vim.fn.strcharpart(truncated, 0, chars - 1)
  end
  return truncated .. ellipsis
end

function M.statusline()
  local cfg = config.get().statusline
  local elements = cfg.elements or {}
  local s = state.current or {}
  if s.status == "inactive" then
    return "NowPlaying: inactive"
  end

  local track = s.track or {}
  local parts = {}
  local text_parts = {}

  if elements.track_title then
    table.insert(text_parts, track.title or "No track")
  end
  if elements.artist and track.artist then
    table.insert(text_parts, track.artist)
  end
  if elements.album and track.album then
    table.insert(text_parts, track.album)
  end

  if elements.status_icon then
    table.insert(parts, format_icon(s.status))
  end

  local text = table.concat(text_parts, cfg.separator or " - ")
  if text ~= "" then
    table.insert(parts, text)
  end

  if elements.player and s.player then
    local label = s.player_label or utils.format_provider(s.player)
    table.insert(parts, string.format("[%s]", label))
  end

  if #parts == 0 then
    return ""
  end

  return truncate(table.concat(parts, " "), cfg.max_length)
end

return M
