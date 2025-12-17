local config = require("player.config")
local utils = require("player.utils")

local M = {}

local function format_message(state)
  if not state or state.status == "inactive" then
    return "No active player"
  end

  local opts = config.get().notify
  local elements = opts.elements or {}
  local track = state.track or {}
  local status_icon = state.status == "playing" and "▶" or "⏸"
  local lines = {}

  -- First line: status icon + title (+ player)
  local main_parts = {}
  if elements.status_icon then
    table.insert(main_parts, status_icon)
  end
  if elements.track_title then
    table.insert(main_parts, track.title or "Unknown")
  end
  if elements.player and state.player then
    local label = state.player_label or utils.format_provider(state.player)
    table.insert(main_parts, string.format("[%s]", label))
  end
  if #main_parts > 0 then
    table.insert(lines, table.concat(main_parts, " "))
  end

  -- Subsequent lines for artist/album
  if elements.artist and track.artist then
    table.insert(lines, "Artist: " .. track.artist)
  end
  if elements.album and track.album then
    table.insert(lines, "Album: " .. track.album)
  end

  if #lines == 0 then
    return state.player or "NowPlaying"
  end

  return table.concat(lines, "\n")
end

function M.show(state)
  local opts = config.get().notify
  if not opts.enabled then
    return
  end

  local msg = format_message(state)
  vim.notify(msg, vim.log.levels.INFO, { title = "NowPlaying.nvim", timeout = opts.timeout })
end

return M
