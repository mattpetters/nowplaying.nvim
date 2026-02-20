local M = {}

local defaults = {
  player_priority = { "apple_music", "spotify", "macos_media" },
  auto_switch = true,
  poll = {
    enabled = true,
    interval_ms = 5000,
  },
  notify = {
    enabled = false,
    timeout = 2500,
    elements = {
      track_title = true,
      artist = true,
      album = true,
      status_icon = true,
      player = true,
    },
  },
  statusline = {
    elements = {
      track_title = true,
      artist = true,
      album = true,
      status_icon = true,
      player = true,
    },
    separator = " - ",
    max_length = 50,
    marquee = {
      enabled = true,
      step_ms = 140,
      pause_ms = 1400,
      gap = "   ",
    },
  },
  keymaps = {
    enabled = true,
    prefix = "<leader>np",
    maps = {
      toggle_panel = "",
      play_pause = "p",
      next_track = "n",
      previous_track = "b",
      stop = "x",
      volume_up = "+",
      volume_down = "-",
      seek_forward = "l",
      seek_backward = "h",
      refresh = "r",
      notify = "i",
      search = "s",
    },
  },
  panel = {
    enabled = true,
    border = { "▛", "▀", "▜", "▐", "▟", "▄", "▙", "▌" },
    draggable = true, -- click and drag to move the panel
    resizable = true, -- click and drag edges/corners to resize
    adaptive_colors = true, -- extract accent color from album art for border
    min_width = 30, -- minimum panel width when resizing
    min_height = 8, -- minimum panel height when resizing
    width = nil, -- fixed width if set; otherwise fallback width
    height = nil, -- fixed height if set; otherwise auto-size
    elements = {
      track_title = true,
      artist = true,
      album = true,
      progress_bar = true,
      volume = true,
      controls = true,
      artwork = {
        enabled = true, -- enable/disable artwork rendering
        cache_dir = vim.fn.stdpath("cache") .. "/nowplaying.nvim",
        download = true, -- download remote artwork (Spotify URLs)
        width = 20,
        height = 10,
      },
    },
  },
  spotify = {
    client_id = nil, -- uses baked-in default; override to use your own Spotify app
    search = {
      debounce_ms = 300,
      limit = 7,     -- results per type (track/album/artist)
      market = nil,  -- ISO 3166-1 alpha-2 country code, e.g. "US"
    },
    actions = {
      default = "play",    -- "play" or "queue"
      secondary = "queue", -- bound to <C-q> in picker
    },
  },
  log_level = "warn",
}

M.options = vim.deepcopy(defaults)

function M.setup(opts)
  opts = opts or {}
  M.options = vim.tbl_deep_extend("force", {}, defaults, opts)
  return M.options
end

function M.get()
  return M.options
end

return M
