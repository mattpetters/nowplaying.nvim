local config = require("player.config")
local state = require("player.state")
local utils = require("player.utils")

local M = {}
local marquee_state = {
  offset = 0,
  dir = 1,
  pause_ticks = 0,
  text_key = nil,
  avail_width = 0,
  max_offset = 0,
}

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

local function take_display(text, width)
  if width <= 0 then
    return ""
  end
  local out = {}
  local out_width = 0
  local chars = vim.fn.strchars(text)
  for i = 0, chars - 1 do
    local ch = vim.fn.strcharpart(text, i, 1)
    local ch_width = vim.fn.strdisplaywidth(ch)
    if out_width + ch_width > width then
      break
    end
    out[#out + 1] = ch
    out_width = out_width + ch_width
    if out_width >= width then
      break
    end
  end
  return table.concat(out)
end

local function drop_display(text, width)
  if width <= 0 then
    return text
  end
  local dropped = 0
  local chars = vim.fn.strchars(text)
  local index = 0
  while index < chars and dropped < width do
    local ch = vim.fn.strcharpart(text, index, 1)
    dropped = dropped + vim.fn.strdisplaywidth(ch)
    index = index + 1
  end
  return vim.fn.strcharpart(text, index, chars - index)
end

local function marquee_window(text, gap, offset, width)
  local scroll_source = text .. gap .. text
  local shifted = drop_display(scroll_source, offset)
  local out = take_display(shifted, width)
  local missing = width - vim.fn.strdisplaywidth(out)
  if missing > 0 then
    out = out .. take_display(text, missing)
  end
  return out
end

local function text_payload(s, cfg, elements)
  local track = s.track or {}
  local parts = {}
  if elements.track_title then
    table.insert(parts, track.title or "No track")
  end
  if elements.artist and track.artist then
    table.insert(parts, track.artist)
  end
  if elements.album and track.album then
    table.insert(parts, track.album)
  end
  return table.concat(parts, cfg.separator or " - ")
end

local function fixed_parts(s, elements)
  local icon = nil
  local player = nil
  if elements.status_icon then
    icon = format_icon(s.status)
  end
  if elements.player and s.player then
    local label = s.player_label or utils.format_provider(s.player)
    player = string.format("[%s]", label)
  end
  return icon, player
end

local function available_middle_width(max_length, icon, player)
  if not max_length or max_length <= 0 then
    return nil
  end
  local width = max_length
  if icon then
    width = width - vim.fn.strdisplaywidth(icon) - 1
  end
  if player then
    width = width - vim.fn.strdisplaywidth(player) - 1
  end
  return width
end

local function build_statusline(icon, middle, player)
  local parts = {}
  if icon then
    parts[#parts + 1] = icon
  end
  if middle and middle ~= "" then
    parts[#parts + 1] = middle
  end
  if player then
    parts[#parts + 1] = player
  end
  return table.concat(parts, " ")
end

local function get_marquee_state(s, cfg, elements)
  local marquee_cfg = cfg.marquee or {}
  local middle = text_payload(s, cfg, elements)
  local icon, player = fixed_parts(s, elements)
  local avail_width = available_middle_width(cfg.max_length, icon, player)
  if not avail_width or avail_width <= 0 or middle == "" then
    return {
      enabled = false,
      middle = middle,
      icon = icon,
      player = player,
      avail_width = avail_width,
      key = nil,
      max_offset = 0,
      gap = marquee_cfg.gap or "   ",
    }
  end

  local gap = marquee_cfg.gap or "   "
  local middle_width = vim.fn.strdisplaywidth(middle)
  local gap_width = vim.fn.strdisplaywidth(gap)
  local max_offset = math.max(middle_width + gap_width - avail_width, 0)
  local enabled = marquee_cfg.enabled and max_offset > 0
  local key = table.concat({ middle, tostring(avail_width), tostring(max_offset), gap }, "\031")
  return {
    enabled = enabled,
    middle = middle,
    icon = icon,
    player = player,
    avail_width = avail_width,
    key = key,
    max_offset = max_offset,
    gap = gap,
  }
end

local function reset_marquee_for_context(ctx)
  marquee_state.offset = 0
  marquee_state.dir = 1
  marquee_state.pause_ticks = 0
  marquee_state.text_key = ctx.key
  marquee_state.avail_width = ctx.avail_width or 0
  marquee_state.max_offset = ctx.max_offset or 0
end

local function pause_steps(cfg)
  local marquee_cfg = cfg.marquee or {}
  local step_ms = tonumber(marquee_cfg.step_ms) or 140
  local pause_ms = tonumber(marquee_cfg.pause_ms) or 0
  if step_ms <= 0 or pause_ms <= 0 then
    return 0
  end
  return math.max(math.floor((pause_ms / step_ms) + 0.5), 0)
end

function M.reset()
  marquee_state.offset = 0
  marquee_state.dir = 1
  marquee_state.pause_ticks = 0
  marquee_state.text_key = nil
  marquee_state.avail_width = 0
  marquee_state.max_offset = 0
end

function M.tick()
  local cfg = config.get().statusline or {}
  local elements = cfg.elements or {}
  local s = state.current or {}
  if s.status == "inactive" then
    return false
  end

  local ctx = get_marquee_state(s, cfg, elements)
  if not ctx.enabled then
    if marquee_state.offset ~= 0 or marquee_state.text_key ~= ctx.key then
      reset_marquee_for_context(ctx)
      return true
    end
    return false
  end

  if marquee_state.text_key ~= ctx.key then
    reset_marquee_for_context(ctx)
    return true
  end

  if marquee_state.pause_ticks > 0 then
    marquee_state.pause_ticks = marquee_state.pause_ticks - 1
    return false
  end

  local next_offset = marquee_state.offset + marquee_state.dir
  if next_offset < 0 then
    next_offset = 0
    marquee_state.dir = 1
    marquee_state.pause_ticks = pause_steps(cfg)
  elseif next_offset > ctx.max_offset then
    next_offset = ctx.max_offset
    marquee_state.dir = -1
    marquee_state.pause_ticks = pause_steps(cfg)
  end

  if next_offset == marquee_state.offset then
    return false
  end
  marquee_state.offset = next_offset
  return true
end

function M.statusline()
  local cfg = config.get().statusline
  local elements = cfg.elements or {}
  local s = state.current or {}
  if s.status == "inactive" then
    return "NowPlaying: inactive"
  end

  local ctx = get_marquee_state(s, cfg, elements)
  local middle = ctx.middle

  if ctx.enabled then
    if marquee_state.text_key ~= ctx.key then
      reset_marquee_for_context(ctx)
    end
    middle = marquee_window(ctx.middle, ctx.gap, marquee_state.offset, ctx.avail_width)
  end

  local line = build_statusline(ctx.icon, middle, ctx.player)
  if line == "" then
    return ""
  end

  return truncate(line, cfg.max_length)
end

return M
