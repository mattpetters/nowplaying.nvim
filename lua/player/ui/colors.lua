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

--- Apply accent color to a floating window via window-local highlight groups.
---@param win number  window ID
---@param accent_hex string  e.g. "#e84393"
function M.apply_accent(win, accent_hex)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end
  if not accent_hex then
    return
  end

  -- Create window-scoped highlight groups
  vim.api.nvim_set_hl(0, "NowPlayingBorder", { fg = accent_hex })
  vim.api.nvim_set_hl(0, "NowPlayingAccent", { fg = accent_hex })

  -- Apply to the window via winhighlight
  local whl = vim.api.nvim_get_option_value("winhighlight", { win = win })
  -- Remove any existing NowPlaying overrides, then append ours
  local parts = {}
  if whl and whl ~= "" then
    for part in whl:gmatch("[^,]+") do
      if not part:match("NowPlaying") then
        table.insert(parts, part)
      end
    end
  end
  table.insert(parts, "FloatBorder:NowPlayingBorder")
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
