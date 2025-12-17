local M = {}

local levels = {
  trace = vim.log.levels.TRACE or vim.log.levels.DEBUG,
  debug = vim.log.levels.DEBUG,
  info = vim.log.levels.INFO,
  warn = vim.log.levels.WARN,
  error = vim.log.levels.ERROR,
}

local current_level = levels.warn

local function level_value(name)
  return levels[string.lower(name)] or levels.warn
end

function M.set_level(name)
  current_level = level_value(name)
end

local function notify(level, msg)
  if level < current_level then
    return
  end
  vim.schedule(function()
    vim.notify(msg, level, { title = "NowPlaying.nvim" })
  end)
end

function M.trace(msg)
  notify(vim.log.levels.TRACE or vim.log.levels.DEBUG, msg)
end

function M.debug(msg)
  notify(vim.log.levels.DEBUG, msg)
end

function M.info(msg)
  notify(vim.log.levels.INFO, msg)
end

function M.warn(msg)
  notify(vim.log.levels.WARN, msg)
end

function M.error(msg)
  notify(vim.log.levels.ERROR, msg)
end

return M
