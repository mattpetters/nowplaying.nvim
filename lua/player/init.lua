local config = require("player.config")
local commands = require("player.commands")
local log = require("player.log")
local state = require("player.state")
local statusline = require("player.ui.statusline")

local M = {}

function M.setup(opts)
  local cfg = config.setup(opts)
  log.set_level(cfg.log_level or "warn")
  commands.setup()
  return M
end

function M.refresh()
  return state.refresh()
end

M.state = state
M.statusline = statusline.statusline

return M
