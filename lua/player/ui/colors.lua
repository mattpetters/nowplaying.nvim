-- Adaptive color extraction from album artwork.
-- Pure color math functions (hex<->RGB<->HSL) plus ImageMagick integration
-- for extracting dominant colors and picking an accent for the panel UI.
local M = {}

--- Parse a hex color string to {r, g, b} (0-255 each).
---@param hex string  e.g. "#FF00AA" or "FF00AA"
---@return number[]|nil  {r, g, b} or nil if invalid
function M.hex_to_rgb(hex)
  if not hex or type(hex) ~= "string" then
    return nil
  end
  local h = hex:gsub("^#", "")
  if #h ~= 6 or not h:match("^%x+$") then
    return nil
  end
  local r = tonumber(h:sub(1, 2), 16)
  local g = tonumber(h:sub(3, 4), 16)
  local b = tonumber(h:sub(5, 6), 16)
  return { r, g, b }
end

--- Convert RGB (0-255 each) to a lowercase hex string "#rrggbb".
---@param r number
---@param g number
---@param b number
---@return string
function M.rgb_to_hex(r, g, b)
  return string.format("#%02x%02x%02x", r, g, b)
end

--- Convert RGB (0-255) to HSL (h: 0-360, s: 0-1, l: 0-1).
---@param r number  0-255
---@param g number  0-255
---@param b number  0-255
---@return number[]  {h, s, l}
function M.rgb_to_hsl(r, g, b)
  local r1 = r / 255
  local g1 = g / 255
  local b1 = b / 255

  local max = math.max(r1, g1, b1)
  local min = math.min(r1, g1, b1)
  local l = (max + min) / 2

  if max == min then
    return { 0, 0, l }
  end

  local d = max - min
  local s
  if l > 0.5 then
    s = d / (2 - max - min)
  else
    s = d / (max + min)
  end

  local h
  if max == r1 then
    h = (g1 - b1) / d + (g1 < b1 and 6 or 0)
  elseif max == g1 then
    h = (b1 - r1) / d + 2
  else
    h = (r1 - g1) / d + 4
  end
  h = h * 60

  return { h, s, l }
end

--- Convert HSL (h: 0-360, s: 0-1, l: 0-1) to RGB (0-255 each).
---@param h number  hue 0-360
---@param s number  saturation 0-1
---@param l number  lightness 0-1
---@return number[]  {r, g, b} each 0-255
function M.hsl_to_rgb(h, s, l)
  if s == 0 then
    local v = math.floor(l * 255 + 0.5)
    return { v, v, v }
  end

  local function hue2rgb(p, q, t)
    if t < 0 then t = t + 1 end
    if t > 1 then t = t - 1 end
    if t < 1 / 6 then return p + (q - p) * 6 * t end
    if t < 1 / 2 then return q end
    if t < 2 / 3 then return p + (q - p) * (2 / 3 - t) * 6 end
    return p
  end

  local q = l < 0.5 and (l * (1 + s)) or (l + s - l * s)
  local p = 2 * l - q
  local hk = h / 360

  local r = hue2rgb(p, q, hk + 1 / 3)
  local g = hue2rgb(p, q, hk)
  local b = hue2rgb(p, q, hk - 1 / 3)

  return {
    math.floor(r * 255 + 0.5),
    math.floor(g * 255 + 0.5),
    math.floor(b * 255 + 0.5),
  }
end

--- Lighten a hex color by shifting its HSL lightness up.
---@param hex string  e.g. "#ff0000"
---@param amount number  0-1, how much to increase lightness
---@return string  lightened hex color
function M.lighten(hex, amount)
  local rgb = M.hex_to_rgb(hex)
  if not rgb then return hex end
  local hsl = M.rgb_to_hsl(rgb[1], rgb[2], rgb[3])
  local new_l = math.min(1, hsl[3] + amount)
  local new_rgb = M.hsl_to_rgb(hsl[1], hsl[2], new_l)
  return M.rgb_to_hex(new_rgb[1], new_rgb[2], new_rgb[3])
end

--- Darken a hex color by shifting its HSL lightness down.
---@param hex string  e.g. "#ff0000"
---@param amount number  0-1, how much to decrease lightness
---@return string  darkened hex color
function M.darken(hex, amount)
  local rgb = M.hex_to_rgb(hex)
  if not rgb then return hex end
  local hsl = M.rgb_to_hsl(rgb[1], rgb[2], rgb[3])
  local new_l = math.max(0, hsl[3] - amount)
  local new_rgb = M.hsl_to_rgb(hsl[1], hsl[2], new_l)
  return M.rgb_to_hex(new_rgb[1], new_rgb[2], new_rgb[3])
end

--- Parse ImageMagick `txt:-` output into a list of hex color strings.
--- Handles both srgb and srgba output formats.
--- ImageMagick output lines look like:
---   0,0: (R,G,B)  #RRGGBB  srgb(...)
---   0,0: (R,G,B,A)  #RRGGBBAA  srgba(...)
---@param output string  raw stdout from `magick ... -unique-colors txt:-`
---@return string[]  list of lowercase "#rrggbb" hex strings
function M.parse_magick_output(output)
  if not output or output == "" then
    return {}
  end

  local colors = {}
  for line in output:gmatch("[^\n]+") do
    -- Skip comment lines
    if not line:match("^#") then
      -- Match hex color: #RRGGBB or #RRGGBBAA
      local hex = line:match("#(%x%x%x%x%x%x)")
      if hex then
        table.insert(colors, "#" .. hex:lower())
      end
    end
  end
  return colors
end

--- Pick the best accent color from a list of hex colors.
--- Filters out near-black, near-white, and low-saturation (gray) colors,
--- then picks the one with the highest saturation.
---@param hex_list string[]  list of "#rrggbb" hex strings
---@return string|nil  best accent hex string, or nil if none suitable
function M.pick_accent(hex_list)
  if not hex_list or #hex_list == 0 then
    return nil
  end

  local best_hex = nil
  local best_sat = -1

  for _, hex in ipairs(hex_list) do
    local rgb = M.hex_to_rgb(hex)
    if rgb then
      local hsl = M.rgb_to_hsl(rgb[1], rgb[2], rgb[3])
      local s = hsl[2]
      local l = hsl[3]

      -- Filter criteria:
      -- - lightness > 0.1 (not near-black)
      -- - lightness < 0.9 (not near-white)
      -- - saturation > 0.15 (not gray)
      if l > 0.1 and l < 0.9 and s > 0.15 then
        if s > best_sat then
          best_sat = s
          best_hex = hex:lower()
        end
      end
    end
  end

  return best_hex
end

--- Extract accent color from an image file asynchronously.
--- Spawns ImageMagick to get dominant colors, picks the best accent,
--- and calls the callback with the result.
---@param image_path string  path to image file
---@param callback fun(hex: string|nil)  called with accent hex or nil
function M.extract_accent(image_path, callback)
  if not image_path or image_path == "" then
    callback(nil)
    return
  end

  if vim.fn.executable("magick") ~= 1 then
    callback(nil)
    return
  end

  local cmd = { "magick", image_path, "-resize", "50x50", "-colors", "5", "-unique-colors", "txt:-" }

  if type(vim.system) == "function" then
    vim.system(cmd, { text = true }, function(res)
      if res.code ~= 0 or not res.stdout or res.stdout == "" then
        vim.schedule(function()
          callback(nil)
        end)
        return
      end
      local colors = M.parse_magick_output(res.stdout)
      local accent = M.pick_accent(colors)
      vim.schedule(function()
        callback(accent)
      end)
    end)
  else
    -- Fallback: synchronous
    local output = vim.fn.system(cmd)
    if vim.v.shell_error ~= 0 then
      callback(nil)
      return
    end
    local colors = M.parse_magick_output(output)
    callback(M.pick_accent(colors))
  end
end

--- Desaturate a hex color by blending its saturation toward zero.
---@param hex string  e.g. "#ff0000"
---@param amount number  0-1, how much to reduce saturation (1 = fully gray)
---@return string  desaturated hex color
function M.desaturate(hex, amount)
  local rgb = M.hex_to_rgb(hex)
  if not rgb then return hex end
  local hsl = M.rgb_to_hsl(rgb[1], rgb[2], rgb[3])
  local new_s = math.max(0, hsl[2] * (1 - amount))
  local new_rgb = M.hsl_to_rgb(hsl[1], new_s, hsl[3])
  return M.rgb_to_hex(new_rgb[1], new_rgb[2], new_rgb[3])
end

--- Apply accent color to a floating window via window-local highlight groups.
--- Creates a muted border tint and a very subtle background wash from the
--- extracted accent so the panel blends with the editor rather than popping.
---@param win number  window ID
---@param accent_hex string  e.g. "#e84393"
function M.apply_accent(win, accent_hex)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end
  if not accent_hex then
    return
  end

  -- Border: use the accent but pull it toward the dark end so it reads
  -- as a subtle colored frame rather than a neon outline.
  local border_hex = M.darken(M.desaturate(accent_hex, 0.3), 0.2)

  -- Background: heavily desaturate and push very close to the editor bg
  -- so it's barely perceptible — a tint, not a paint bucket.
  local bg_hex = M.desaturate(M.lighten(accent_hex, 0.38), 0.75)

  -- Create highlight groups for the accent theme
  vim.api.nvim_set_hl(0, "NowPlayingBorder", { fg = border_hex })
  vim.api.nvim_set_hl(0, "NowPlayingBg", { bg = bg_hex })
  vim.api.nvim_set_hl(0, "NowPlayingAccent", { fg = accent_hex, bg = bg_hex })

  -- Apply to the window via winhighlight
  local whl = vim.api.nvim_get_option_value("winhighlight", { win = win })
  local parts = {}
  if whl and whl ~= "" then
    for part in whl:gmatch("[^,]+") do
      if not part:match("NowPlaying") then
        table.insert(parts, part)
      end
    end
  end
  table.insert(parts, "FloatBorder:NowPlayingBorder")
  table.insert(parts, "Normal:NowPlayingBg")
  vim.api.nvim_set_option_value("winhighlight", table.concat(parts, ","), { win = win })
end

--- Clear accent-related highlight groups from a window.
---@param win number  window ID
function M.clear_accent(win)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end
  local whl = vim.api.nvim_get_option_value("winhighlight", { win = win })
  if not whl or whl == "" then
    return
  end
  local parts = {}
  for part in whl:gmatch("[^,]+") do
    if not part:match("NowPlaying") then
      table.insert(parts, part)
    end
  end
  vim.api.nvim_set_option_value("winhighlight", table.concat(parts, ","), { win = win })
end

return M
