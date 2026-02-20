-- Telescope extension entry point for nowplaying_spotify
-- Usage: :Telescope nowplaying_spotify
--   or:  require("telescope").extensions.nowplaying_spotify.search()
return require("telescope").register_extension({
  exports = {
    search = function(opts)
      require("player.telescope.search").open(opts)
    end,
    -- default action when calling :Telescope nowplaying_spotify
    nowplaying_spotify = function(opts)
      require("player.telescope.search").open(opts)
    end,
  },
})
