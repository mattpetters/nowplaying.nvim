-- Test helpers for nowplaying.nvim
-- Provides child Neovim process management for functional/UI tests.
local H = {}

-- Project root (one level up from tests/)
H.project_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")

-- Counter for unique child luacov stats filenames
local child_counter = 0

--- Create and start a child Neovim process with the plugin on rtp
---@return table child  MiniTest child neovim handle
function H.new_child()
  local child = MiniTest.new_child_neovim()
  child.start({ "-u", "NONE" })
  -- Add project root to runtimepath so require("player.*") works
  child.lua(string.format([[vim.opt.rtp:prepend(%q)]], H.project_root))

  -- Inject luacov into the child process when COVERAGE=1
  if os.getenv("COVERAGE") == "1" then
    child_counter = child_counter + 1
    child.lua(string.format([[
      local home = os.getenv("HOME") or ""
      package.path = home .. "/.luarocks/share/lua/5.1/?.lua;"
                  .. home .. "/.luarocks/share/lua/5.1/?/init.lua;"
                  .. package.path
      local ok, luacov = pcall(require, "luacov.runner")
      if ok then
        luacov.init({
          statsfile = %q,
          include = { "player/" },
          exclude = { "tests/", "scripts/", "deps/", "mini%%.", "telescope%%.", "image%%." },
        })
      end
    ]], H.project_root .. "/luacov.stats.child." .. child_counter .. ".out"))

    -- Wrap child.stop to flush luacov stats before killing the process
    local orig_stop = child.stop
    child.stop = function(...)
      pcall(child.lua, [[
        local ok, luacov = pcall(require, "luacov.runner")
        if ok and luacov.save_stats then luacov.save_stats() end
      ]])
      return orig_stop(...)
    end
  end

  return child
end

--- Set up the plugin with config in the child process
---@param child table  child neovim handle
---@param opts? table  config overrides for require("player.config").setup()
function H.setup_plugin(child, opts)
  local opts_str = vim.inspect(opts or {})
  child.lua(string.format([[
    -- Initialise config (does not start providers/polling)
    require("player.config").setup(%s)
  ]], opts_str))
end

--- Build a fake state snapshot for testing panel rendering
---@param overrides? table
---@return table
function H.make_state(overrides)
  return vim.tbl_deep_extend("force", {
    status = "playing",
    player = "test",
    player_label = "Test",
    position = 90,
    volume = 75,
    track = {
      title = "Test Track",
      artist = "Test Artist",
      album = "Test Album",
      duration = 240,
    },
    artwork = nil,
  }, overrides or {})
end

--- Inject a state snapshot into the child process and return it
---@param child table
---@param snapshot? table  defaults to H.make_state()
function H.set_state(child, snapshot)
  local s = snapshot or H.make_state()
  child.lua(string.format([[
    require("player.state").current = %s
  ]], vim.inspect(s)))
end

--- Open the panel in the child process with an optional state snapshot
---@param child table
---@param snapshot? table
function H.open_panel(child, snapshot)
  local s = snapshot or H.make_state()
  child.lua(string.format([[
    local panel = require("player.ui.panel")
    panel.open(%s)
  ]], vim.inspect(s)))
end

--- Get the floating window id from the child (or vim.NIL if closed)
---@param child table
---@return number|nil
function H.get_panel_win(child)
  return child.lua_get([[
    (function()
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        local cfg = vim.api.nvim_win_get_config(w)
        if cfg.relative and cfg.relative ~= "" then
          return w
        end
      end
      return nil
    end)()
  ]])
end

return H
