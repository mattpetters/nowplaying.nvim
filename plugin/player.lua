if vim.g.loaded_now_playing_plugin then
  return
end
vim.g.loaded_now_playing_plugin = true

local ok, player = pcall(require, "player")
if not ok then
  vim.notify("[NowPlaying.nvim] failed to load: " .. player, vim.log.levels.ERROR)
  return
end

player.setup()
