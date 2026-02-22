-- Unit tests for the colors module (adaptive accent color from album art)
-- Tests pure color math functions: hex<->RGB, RGB<->HSL, ImageMagick
-- output parsing, and accent color selection.
local H = dofile("tests/helpers.lua")

local T = MiniTest.new_set({
  hooks = {
    pre_once = function()
      _G.child = H.new_child()
      child.lua([[_G.colors = require("player.ui.colors")]])
    end,
    post_once = function()
      child.stop()
    end,
    pre_case = function()
      child.lua([[
        package.loaded["player.ui.colors"] = nil
        _G.colors = require("player.ui.colors")
      ]])
    end,
  },
})

-- ── hex_to_rgb ─────────────────────────────────────────────────

T["hex_to_rgb"] = MiniTest.new_set()

T["hex_to_rgb"]["parses 6-digit hex with hash"] = function()
  local rgb = child.lua_get([[colors.hex_to_rgb("#FF0000")]])
  MiniTest.expect.equality(rgb, { 255, 0, 0 })
end

T["hex_to_rgb"]["parses 6-digit hex without hash"] = function()
  local rgb = child.lua_get([[colors.hex_to_rgb("00FF00")]])
  MiniTest.expect.equality(rgb, { 0, 255, 0 })
end

T["hex_to_rgb"]["parses lowercase hex"] = function()
  local rgb = child.lua_get([[colors.hex_to_rgb("#0000ff")]])
  MiniTest.expect.equality(rgb, { 0, 0, 255 })
end

T["hex_to_rgb"]["parses mixed case"] = function()
  local rgb = child.lua_get([[colors.hex_to_rgb("#2D9FDA")]])
  MiniTest.expect.equality(rgb, { 45, 159, 218 })
end

T["hex_to_rgb"]["returns nil for invalid input"] = function()
  local rgb = child.lua_get([[colors.hex_to_rgb("not-a-color")]])
  MiniTest.expect.equality(rgb, vim.NIL)
end

-- ── rgb_to_hex ─────────────────────────────────────────────────

T["rgb_to_hex"] = MiniTest.new_set()

T["rgb_to_hex"]["converts red"] = function()
  local hex = child.lua_get([[colors.rgb_to_hex(255, 0, 0)]])
  MiniTest.expect.equality(hex, "#ff0000")
end

T["rgb_to_hex"]["converts arbitrary color"] = function()
  local hex = child.lua_get([[colors.rgb_to_hex(45, 159, 218)]])
  MiniTest.expect.equality(hex, "#2d9fda")
end

T["rgb_to_hex"]["zero-pads single digit values"] = function()
  local hex = child.lua_get([[colors.rgb_to_hex(0, 5, 10)]])
  MiniTest.expect.equality(hex, "#00050a")
end

-- ── rgb_to_hsl ─────────────────────────────────────────────────

T["rgb_to_hsl"] = MiniTest.new_set()

T["rgb_to_hsl"]["pure red"] = function()
  local hsl = child.lua_get([[colors.rgb_to_hsl(255, 0, 0)]])
  -- H=0, S=1, L=0.5
  MiniTest.expect.equality(hsl[1], 0)
  MiniTest.expect.equality(hsl[2], 1)
  MiniTest.expect.equality(hsl[3], 0.5)
end

T["rgb_to_hsl"]["pure white"] = function()
  local hsl = child.lua_get([[colors.rgb_to_hsl(255, 255, 255)]])
  MiniTest.expect.equality(hsl[2], 0)   -- saturation = 0
  MiniTest.expect.equality(hsl[3], 1)   -- lightness = 1
end

T["rgb_to_hsl"]["pure black"] = function()
  local hsl = child.lua_get([[colors.rgb_to_hsl(0, 0, 0)]])
  MiniTest.expect.equality(hsl[2], 0)   -- saturation = 0
  MiniTest.expect.equality(hsl[3], 0)   -- lightness = 0
end

T["rgb_to_hsl"]["mid gray has zero saturation"] = function()
  local hsl = child.lua_get([[colors.rgb_to_hsl(128, 128, 128)]])
  MiniTest.expect.equality(hsl[2], 0)
end

-- ── parse_magick_output ────────────────────────────────────────

T["parse_magick_output"] = MiniTest.new_set()

T["parse_magick_output"]["extracts hex colors from ImageMagick txt output"] = function()
  local output = [[# ImageMagick pixel enumeration: 5,1,0,255,srgba
0,0: (63,142,146,1)  #3F8E9201  srgba(24.7165%,55.8601%,57.2064%,0.00428312)
1,0: (44,128,166,84)  #2C80A654  srgba(17.2353%,50.0041%,65.2579%,0.3288)
2,0: (94,175,92,235)  #5EAF5CEB  srgba(36.8175%,68.7933%,36.1917%,0.92239)
3,0: (25,110,195,243)  #196EC3F3  srgba(9.79999%,43.0792%,76.5556%,0.954733)
4,0: (45,159,218,252)  #2D9FDAFC  srgba(17.7763%,62.2133%,85.3605%,0.987018)]]

  local result = child.lua_get(string.format([[colors.parse_magick_output(%q)]], output))
  -- Should extract 5 hex colors (6-digit, dropping the alpha bytes)
  MiniTest.expect.equality(#result, 5)
  MiniTest.expect.equality(result[1], "#3f8e92")
  MiniTest.expect.equality(result[5], "#2d9fda")
end

T["parse_magick_output"]["handles srgb output without alpha"] = function()
  local output = [[# ImageMagick pixel enumeration: 3,1,0,255,srgb
0,0: (255,0,0)  #FF0000  srgb(100%,0%,0%)
1,0: (0,128,0)  #008000  srgb(0%,50.1961%,0%)
2,0: (0,0,255)  #0000FF  srgb(0%,0%,100%)]]

  local result = child.lua_get(string.format([[colors.parse_magick_output(%q)]], output))
  MiniTest.expect.equality(#result, 3)
  MiniTest.expect.equality(result[1], "#ff0000")
  MiniTest.expect.equality(result[2], "#008000")
  MiniTest.expect.equality(result[3], "#0000ff")
end

T["parse_magick_output"]["returns empty table for empty input"] = function()
  local result = child.lua_get([[colors.parse_magick_output("")]])
  MiniTest.expect.equality(#result, 0)
end

T["parse_magick_output"]["ignores comment line"] = function()
  local output = [[# ImageMagick pixel enumeration: 1,1,0,255,srgb
0,0: (100,200,50)  #64C832  srgb(39.2%,78.4%,19.6%)]]
  local result = child.lua_get(string.format([[colors.parse_magick_output(%q)]], output))
  MiniTest.expect.equality(#result, 1)
  MiniTest.expect.equality(result[1], "#64c832")
end

-- ── pick_accent ────────────────────────────────────────────────

T["pick_accent"] = MiniTest.new_set()

T["pick_accent"]["picks the most saturated color"] = function()
  -- Red is fully saturated, gray is not
  local result = child.lua_get([[colors.pick_accent({"#808080", "#FF0000", "#C0C0C0"})]])
  MiniTest.expect.equality(result, "#ff0000")
end

T["pick_accent"]["filters out near-black"] = function()
  -- Only near-black colors -> should return nil
  local result = child.lua_get([[colors.pick_accent({"#0A0A0A", "#050505", "#0F0F0F"})]])
  MiniTest.expect.equality(result, vim.NIL)
end

T["pick_accent"]["filters out near-white"] = function()
  local result = child.lua_get([[colors.pick_accent({"#F5F5F5", "#FAFAFA", "#FFFFFF"})]])
  MiniTest.expect.equality(result, vim.NIL)
end

T["pick_accent"]["filters out grays (low saturation)"] = function()
  local result = child.lua_get([[colors.pick_accent({"#808080", "#909090", "#707070"})]])
  MiniTest.expect.equality(result, vim.NIL)
end

T["pick_accent"]["returns nil for empty list"] = function()
  local result = child.lua_get([[colors.pick_accent({})]])
  MiniTest.expect.equality(result, vim.NIL)
end

T["pick_accent"]["picks vibrant color over muted one"] = function()
  -- Bright blue vs muted brownish
  local result = child.lua_get([[colors.pick_accent({"#8B7355", "#2D9FDA"})]])
  MiniTest.expect.equality(result, "#2d9fda")
end

T["pick_accent"]["accepts single viable color"] = function()
  local result = child.lua_get([[colors.pick_accent({"#E84393"})]])
  MiniTest.expect.equality(result, "#e84393")
end

-- ── desaturate ─────────────────────────────────────────────────

T["desaturate"] = MiniTest.new_set()

T["desaturate"]["reduces saturation by given fraction"] = function()
  -- Pure red (H=0, S=1, L=0.5) desaturated by 0.5 → S=0.5
  local hex = child.lua_get([[colors.desaturate("#ff0000", 0.5)]])
  local rgb = child.lua_get(string.format([[colors.hex_to_rgb(%q)]], hex))
  -- S=0.5, L=0.5 → R~191, G~64, B~64
  MiniTest.expect.equality(rgb[1] > rgb[2], true) -- red channel still dominant
  MiniTest.expect.equality(rgb[2], rgb[3])         -- green == blue (symmetric)
  MiniTest.expect.equality(rgb[2] > 50, true)      -- not fully saturated anymore
end

T["desaturate"]["amount=0 keeps color unchanged"] = function()
  local hex = child.lua_get([[colors.desaturate("#2d9fda", 0)]])
  MiniTest.expect.equality(hex, "#2d9fda")
end

T["desaturate"]["amount=1 fully desaturates to gray"] = function()
  local hex = child.lua_get([[colors.desaturate("#ff0000", 1)]])
  local rgb = child.lua_get(string.format([[colors.hex_to_rgb(%q)]], hex))
  -- Fully desaturated red at L=0.5 → mid gray
  MiniTest.expect.equality(rgb[1], rgb[2])
  MiniTest.expect.equality(rgb[2], rgb[3])
end

T["desaturate"]["returns input for invalid hex"] = function()
  local hex = child.lua_get([[colors.desaturate("not-a-color", 0.5)]])
  MiniTest.expect.equality(hex, "not-a-color")
end

-- ── hsl_to_rgb ─────────────────────────────────────────────────

T["hsl_to_rgb"] = MiniTest.new_set()

T["hsl_to_rgb"]["pure red"] = function()
  local rgb = child.lua_get([[colors.hsl_to_rgb(0, 1, 0.5)]])
  MiniTest.expect.equality(rgb, { 255, 0, 0 })
end

T["hsl_to_rgb"]["pure green"] = function()
  local rgb = child.lua_get([[colors.hsl_to_rgb(120, 1, 0.5)]])
  MiniTest.expect.equality(rgb, { 0, 255, 0 })
end

T["hsl_to_rgb"]["pure blue"] = function()
  local rgb = child.lua_get([[colors.hsl_to_rgb(240, 1, 0.5)]])
  MiniTest.expect.equality(rgb, { 0, 0, 255 })
end

T["hsl_to_rgb"]["white"] = function()
  local rgb = child.lua_get([[colors.hsl_to_rgb(0, 0, 1)]])
  MiniTest.expect.equality(rgb, { 255, 255, 255 })
end

T["hsl_to_rgb"]["black"] = function()
  local rgb = child.lua_get([[colors.hsl_to_rgb(0, 0, 0)]])
  MiniTest.expect.equality(rgb, { 0, 0, 0 })
end

T["hsl_to_rgb"]["mid gray"] = function()
  local rgb = child.lua_get([[colors.hsl_to_rgb(0, 0, 0.5)]])
  MiniTest.expect.equality(rgb, { 128, 128, 128 })
end

-- ── lighten / darken ───────────────────────────────────────────

T["lighten"] = MiniTest.new_set()

T["lighten"]["lightens a color by given amount"] = function()
  -- Pure red (L=0.5) lightened by 0.4 → L=0.9
  local hex = child.lua_get([[colors.lighten("#ff0000", 0.4)]])
  -- H=0, S=1, L=0.9 → very light red/pink
  local rgb = child.lua_get(string.format([[colors.hex_to_rgb(%q)]], hex))
  -- L=0.9 should give a light pinkish red
  MiniTest.expect.equality(rgb[1] > 200, true)
  MiniTest.expect.equality(rgb[2] > 100, true)
end

T["lighten"]["clamps at lightness 1.0"] = function()
  -- Already light color lightened a lot → should not exceed white
  local hex = child.lua_get([[colors.lighten("#ffcccc", 0.5)]])
  local rgb = child.lua_get(string.format([[colors.hex_to_rgb(%q)]], hex))
  MiniTest.expect.equality(rgb[1] <= 255, true)
  MiniTest.expect.equality(rgb[2] <= 255, true)
  MiniTest.expect.equality(rgb[3] <= 255, true)
end

T["darken"] = MiniTest.new_set()

T["darken"]["darkens a color by given amount"] = function()
  -- Pure red (L=0.5) darkened by 0.3 → L=0.2
  local hex = child.lua_get([[colors.darken("#ff0000", 0.3)]])
  local rgb = child.lua_get(string.format([[colors.hex_to_rgb(%q)]], hex))
  -- Should be a dark red
  MiniTest.expect.equality(rgb[1] > 50, true)
  MiniTest.expect.equality(rgb[1] < 150, true)
  MiniTest.expect.equality(rgb[2] < 20, true)
end

T["darken"]["clamps at lightness 0.0"] = function()
  local hex = child.lua_get([[colors.darken("#330000", 0.9)]])
  local rgb = child.lua_get(string.format([[colors.hex_to_rgb(%q)]], hex))
  MiniTest.expect.equality(rgb[1] >= 0, true)
  MiniTest.expect.equality(rgb[2] >= 0, true)
  MiniTest.expect.equality(rgb[3] >= 0, true)
end

-- ── apply_accent background subtlety ───────────────────────────
-- The panel background should be a very subtle tint — almost matching
-- the editor background — not an opaque wash of the album art color.

T["apply_accent_bg"] = MiniTest.new_set()

T["apply_accent_bg"]["background stays dark for bright accent (low lightness)"] = function()
  -- Simulate what apply_accent produces for a bright/white-ish accent
  -- The generated BG hex should have lightness < 0.25 (very dark, subtle tint)
  local bg_hex = child.lua_get([[
    (function()
      local c = colors
      local accent = "#ffffff"  -- worst case: white album art
      -- This replicates the bg_hex formula in apply_accent
      local bg = c.desaturate(c.darken(accent, 0.80), 0.90)
      return bg
    end)()
  ]])
  local rgb = child.lua_get(string.format([[colors.hex_to_rgb(%q)]], bg_hex))
  local hsl = child.lua_get(string.format([[colors.rgb_to_hsl(%d, %d, %d)]], rgb[1], rgb[2], rgb[3]))
  -- Lightness should be very low (< 0.25) for a subtle dark tint
  MiniTest.expect.equality(hsl[3] < 0.25, true)
end

T["apply_accent_bg"]["background stays dark for vivid red accent"] = function()
  local bg_hex = child.lua_get([[
    (function()
      local c = colors
      local accent = "#ff0000"
      local bg = c.desaturate(c.darken(accent, 0.80), 0.90)
      return bg
    end)()
  ]])
  local rgb = child.lua_get(string.format([[colors.hex_to_rgb(%q)]], bg_hex))
  local hsl = child.lua_get(string.format([[colors.rgb_to_hsl(%d, %d, %d)]], rgb[1], rgb[2], rgb[3]))
  MiniTest.expect.equality(hsl[3] < 0.25, true)
end

T["apply_accent_bg"]["background is nearly neutral (low saturation)"] = function()
  local bg_hex = child.lua_get([[
    (function()
      local c = colors
      local accent = "#e84393"  -- vibrant pink
      local bg = c.desaturate(c.darken(accent, 0.80), 0.90)
      return bg
    end)()
  ]])
  local rgb = child.lua_get(string.format([[colors.hex_to_rgb(%q)]], bg_hex))
  local hsl = child.lua_get(string.format([[colors.rgb_to_hsl(%d, %d, %d)]], rgb[1], rgb[2], rgb[3]))
  -- Saturation should be very low (< 0.15) for near-neutral
  MiniTest.expect.equality(hsl[2] < 0.15, true)
end

return T
