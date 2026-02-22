-- scripts/minitest.lua
-- Headless test runner for mini.test.
-- Usage: nvim --headless -u scripts/minitest.lua

-- Resolve project root (one level up from scripts/)
local project_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local deps_dir = project_root .. "/deps"

-- Bootstrap mini.nvim if not present
local mini_path = deps_dir .. "/mini.nvim"
if not vim.loop.fs_stat(mini_path) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/echasnovski/mini.nvim",
    mini_path,
  })
end

-- Add deps and project to runtimepath
vim.opt.rtp:prepend(mini_path)
vim.opt.rtp:prepend(project_root)

-- Add luarocks paths for luacov
local home = os.getenv("HOME") or ""
local luarocks_share = home .. "/.luarocks/share/lua/5.1/?.lua"
local luarocks_share_init = home .. "/.luarocks/share/lua/5.1/?/init.lua"
package.path = luarocks_share .. ";" .. luarocks_share_init .. ";" .. package.path

-- Disable swap/backup/undo for clean test runs
vim.o.swapfile = false
vim.o.backup = false
vim.o.writebackup = false
vim.o.undofile = false

-- Enable luacov if COVERAGE=1 is set (via environment variable)
if os.getenv("COVERAGE") == "1" then
  local ok, luacov = pcall(require, "luacov.runner")
  if ok then
    luacov.init({
      statsfile = project_root .. "/luacov.stats.out",
      include = { "player/" },
      exclude = { "tests/", "scripts/", "deps/", "mini%.", "telescope%.", "image%." },
    })
  end
end

-- Set up mini.test with stdout reporter for CI / headless use
require("mini.test").setup({
  collect = {
    find_files = function()
      return vim.fn.globpath(project_root .. "/tests", "**/test_*.lua", true, true)
    end,
  },
  execute = {
    reporter = require("mini.test").gen_reporter.stdout({ quit_on_finish = true }),
  },
})

-- Run all tests
MiniTest.run()
