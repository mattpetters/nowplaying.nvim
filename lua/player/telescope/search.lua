local client = require("player.spotify_api.client")
local auth = require("player.spotify_api.auth")
local config = require("player.config")
local log = require("player.log")

local M = {}

-- Nerd Font icons
local ICONS = {
  track = "\u{f001}",    -- nf-fa-music
  album = "\u{f51f}",    -- nf-md-album
  artist = "\u{f0f3d}",  -- nf-md-account_music
  playlist = "\u{f0cb0}", -- nf-md-playlist_music
  loading = "\u{f251}",  -- nf-fa-hourglass_half
  spotify = "\u{f1bc}",  -- nf-fa-spotify
  play = "\u{f04b}",     -- nf-fa-play
  queue = "\u{f0c9}",    -- nf-fa-bars (list)
  clock = "\u{f017}",    -- nf-fa-clock_o
  fire = "\u{f490}",     -- nf-md-fire
  calendar = "\u{f073}", -- nf-fa-calendar
  people = "\u{f0c0}",   -- nf-fa-users
  tag = "\u{f02b}",      -- nf-fa-tag
  owner = "\u{f007}",    -- nf-fa-user
}

-- --------------------------------------------------------------------------
-- Formatting helpers
-- --------------------------------------------------------------------------

local function format_duration(ms)
  if not ms then return "" end
  local total_sec = math.floor(ms / 1000)
  local min = math.floor(total_sec / 60)
  local sec = total_sec % 60
  return string.format("%d:%02d", min, sec)
end

local function format_number(n)
  if not n or n == 0 then return "0" end
  if n >= 1000000 then
    return string.format("%.1fM", n / 1000000)
  elseif n >= 1000 then
    return string.format("%.1fK", n / 1000)
  end
  return tostring(n)
end

--- Build a popularity bar: ████░░░░░░ 72
local function popularity_bar(pop, width)
  width = width or 10
  if not pop then return string.rep("\u{2591}", width) .. "  ?" end
  local filled = math.floor(pop / 100 * width + 0.5)
  local empty = width - filled
  return string.rep("\u{2588}", filled) .. string.rep("\u{2591}", empty) .. " " .. tostring(pop)
end

local function release_year(date_str)
  if not date_str or date_str == "" then return nil end
  return date_str:match("^(%d%d%d%d)")
end

-- --------------------------------------------------------------------------
-- Entry maker with Telescope displayer for columnar layout
-- --------------------------------------------------------------------------

local function get_entry_maker()
  local entry_display = require("telescope.pickers.entry_display")

  local displayer = entry_display.create({
    separator = " ",
    items = {
      { width = 2 },  -- icon
      { width = 7 },  -- type tag
      { remaining = true }, -- main text
    },
  })

  return function(item)
    local icon = ICONS[item.type] or ""
    local type_tag = ({ track = "Track", album = "Album", artist = "Artist", playlist = "List" })[item.type] or ""
    local main_text

    if item.type == "track" then
      local dur = format_duration(item.duration_ms)
      main_text = item.name .. "  \u{2014}  " .. item.artist
      if dur ~= "" then
        main_text = main_text .. "  " .. ICONS.clock .. " " .. dur
      end
    elseif item.type == "album" then
      main_text = item.name .. "  \u{2014}  " .. item.artist
      local year = release_year(item.release_date)
      if year then
        main_text = main_text .. "  " .. ICONS.calendar .. " " .. year
      end
      if item.total_tracks then
        main_text = main_text .. "  (" .. item.total_tracks .. " tracks)"
      end
    elseif item.type == "artist" then
      main_text = item.name
      if item.genres and item.genres ~= "" then
        main_text = main_text .. "  \u{2014}  " .. item.genres
      end
      if item.followers and item.followers > 0 then
        main_text = main_text .. "  " .. ICONS.people .. " " .. format_number(item.followers)
      end
    elseif item.type == "playlist" then
      main_text = item.name
      if item.owner and item.owner ~= "" then
        main_text = main_text .. "  \u{2014}  " .. ICONS.owner .. " " .. item.owner
      end
      if item.total_tracks and item.total_tracks > 0 then
        main_text = main_text .. "  (" .. item.total_tracks .. " tracks)"
      end
    else
      main_text = item.name or "Unknown"
    end

    return {
      value = item,
      ordinal = (item.name or "") .. " " .. (item.artist or "") .. " " .. (item.album or "") .. " " .. (item.owner or ""),
      display = function(entry)
        return displayer({
          { icon, "NowPlayingSearchIcon" },
          { type_tag, "NowPlayingSearchType" },
          { main_text, "NowPlayingSearchText" },
        })
      end,
    }
  end
end

-- --------------------------------------------------------------------------
-- Card-style previewer
-- --------------------------------------------------------------------------

local function make_previewer()
  local previewers = require("telescope.previewers")

  return previewers.new_buffer_previewer({
    title = "Details",
    define_preview = function(self, entry, _status)
      local item = entry.value
      if not item then return end

      local bufnr = self.state.bufnr
      local lines = {}
      local highlights = {} -- { {line_0idx, col_start, col_end, hl_group} }

      local function add(text, hl)
        table.insert(lines, text)
        if hl then
          table.insert(highlights, { #lines - 1, 0, #text, hl })
        end
      end

      local function add_field(icon, label, value, hl)
        if value and value ~= "" then
          local text = "  " .. icon .. "  " .. label .. ": " .. tostring(value)
          table.insert(lines, text)
          if hl then
            table.insert(highlights, { #lines - 1, 0, #text, hl })
          end
        end
      end

      -- Header
      local type_icon = ICONS[item.type] or ""
      local type_label = ({ track = "TRACK", album = "ALBUM", artist = "ARTIST", playlist = "PLAYLIST" })[item.type] or ""
      add("")
      add("  " .. type_icon .. "  " .. type_label, "NowPlayingPreviewHeader")
      add("  " .. string.rep("\u{2500}", 40), "NowPlayingPreviewBorder")
      add("")

      -- Name (big)
      add("  " .. (item.name or "Unknown"), "NowPlayingPreviewTitle")
      add("")

      if item.type == "track" then
        add_field(ICONS.artist, "Artist", item.artist, "NowPlayingPreviewField")
        add_field(ICONS.album, "Album", item.album, "NowPlayingPreviewField")
        add_field(ICONS.clock, "Duration", format_duration(item.duration_ms), "NowPlayingPreviewField")
        if item.popularity then
          add("")
          add("  " .. ICONS.fire .. "  Popularity", "NowPlayingPreviewField")
          add("  " .. "   " .. popularity_bar(item.popularity, 20), "NowPlayingPreviewBar")
        end
      elseif item.type == "album" then
        add_field(ICONS.artist, "Artist", item.artist, "NowPlayingPreviewField")
        add_field(ICONS.calendar, "Released", release_year(item.release_date), "NowPlayingPreviewField")
        add_field(ICONS.track, "Tracks", item.total_tracks, "NowPlayingPreviewField")
      elseif item.type == "artist" then
        if item.genres and item.genres ~= "" then
          add_field(ICONS.tag, "Genres", item.genres, "NowPlayingPreviewField")
        end
        if item.followers and item.followers > 0 then
          add_field(ICONS.people, "Followers", format_number(item.followers), "NowPlayingPreviewField")
        end
        if item.popularity then
          add("")
          add("  " .. ICONS.fire .. "  Popularity", "NowPlayingPreviewField")
          add("  " .. "   " .. popularity_bar(item.popularity, 20), "NowPlayingPreviewBar")
        end
      elseif item.type == "playlist" then
        add_field(ICONS.owner, "By", item.owner, "NowPlayingPreviewField")
        add_field(ICONS.track, "Tracks", item.total_tracks, "NowPlayingPreviewField")
        if item.description and item.description ~= "" then
          add("")
          -- Strip HTML tags from description (Spotify returns HTML sometimes)
          local desc = item.description:gsub("<[^>]+>", "")
          add("  " .. desc, "NowPlayingPreviewField")
        end
      end

      -- Controls hint
      add("")
      add("  " .. string.rep("\u{2500}", 40), "NowPlayingPreviewBorder")
      add("")
      local hints = {}
      if item.type == "track" then
        table.insert(hints, "  " .. ICONS.play .. "  <CR> Play   " .. ICONS.queue .. "  <C-q> Queue")
      elseif item.type == "album" then
        table.insert(hints, "  " .. ICONS.play .. "  <CR> Browse tracks")
      elseif item.type == "artist" then
        table.insert(hints, "  " .. ICONS.play .. "  <CR> Top tracks")
      elseif item.type == "playlist" then
        table.insert(hints, "  " .. ICONS.play .. "  <CR> Browse tracks")
      end
      for _, h in ipairs(hints) do
        add(h, "NowPlayingPreviewHint")
      end

      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Apply highlights
      for _, hl in ipairs(highlights) do
        pcall(vim.api.nvim_buf_add_highlight, bufnr, -1, hl[4], hl[1], hl[2], hl[3])
      end
    end,
  })
end

-- --------------------------------------------------------------------------
-- Highlight groups
-- --------------------------------------------------------------------------

local function setup_highlights()
  local function hi(name, opts)
    -- Only set if not already user-overridden
    pcall(vim.api.nvim_set_hl, 0, name, opts)
  end
  hi("NowPlayingSearchIcon", { link = "Special", default = true })
  hi("NowPlayingSearchType", { link = "Comment", default = true })
  hi("NowPlayingSearchText", { link = "Normal", default = true })
  hi("NowPlayingPreviewHeader", { link = "Title", default = true })
  hi("NowPlayingPreviewBorder", { link = "FloatBorder", default = true })
  hi("NowPlayingPreviewTitle", { bold = true, link = "String", default = true })
  hi("NowPlayingPreviewField", { link = "Normal", default = true })
  hi("NowPlayingPreviewBar", { link = "Special", default = true })
  hi("NowPlayingPreviewHint", { link = "Comment", default = true })
  hi("NowPlayingLoading", { link = "Comment", default = true })
end

-- --------------------------------------------------------------------------
-- Loading entry
-- --------------------------------------------------------------------------

local loading_frames = { "\u{280b}", "\u{2819}", "\u{2839}", "\u{2838}", "\u{283c}", "\u{2834}", "\u{2826}", "\u{2827}", "\u{2807}", "\u{280f}" }
local loading_idx = 0

local function make_loading_entry()
  loading_idx = (loading_idx % #loading_frames) + 1
  local frame = loading_frames[loading_idx]
  return {
    value = { type = "loading", name = "Searching..." },
    ordinal = "loading",
    display = function()
      return frame .. " Searching Spotify..."
    end,
  }
end

-- --------------------------------------------------------------------------
-- Track list picker (drill-down for albums/artists)
-- --------------------------------------------------------------------------

local function open_track_list(tracks, title)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  setup_highlights()
  local entry_maker = get_entry_maker()

  pickers.new({}, {
    prompt_title = title or "Spotify Tracks",
    finder = finders.new_table({
      results = tracks,
      entry_maker = entry_maker,
    }),
    sorter = conf.generic_sorter({}),
    previewer = make_previewer(),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if selection and selection.value and selection.value.uri then
          client.play(selection.value.uri, function(ok, err)
            if ok then
              vim.notify("Playing: " .. selection.value.name, vim.log.levels.INFO, { title = "NowPlaying.nvim" })
            else
              vim.notify("Play failed: " .. (err or "unknown"), vim.log.levels.ERROR, { title = "NowPlaying.nvim" })
            end
          end)
        end
      end)

      local function queue_selected()
        local selection = action_state.get_selected_entry()
        if selection and selection.value and selection.value.type == "track" then
          client.queue(selection.value.uri, function(ok, err)
            if ok then
              vim.notify("Queued: " .. selection.value.name, vim.log.levels.INFO, { title = "NowPlaying.nvim" })
            else
              vim.notify("Queue failed: " .. (err or "unknown"), vim.log.levels.ERROR, { title = "NowPlaying.nvim" })
            end
          end)
        end
      end

      map("i", "<C-q>", queue_selected)
      map("n", "<C-q>", queue_selected)
      return true
    end,
  }):find()
end

-- --------------------------------------------------------------------------
-- Handle result selection
-- --------------------------------------------------------------------------

local function handle_selection(item, action)
  if not item or item.type == "loading" then return end
  action = action or "play"

  if item.type == "track" then
    if action == "queue" then
      client.queue(item.uri, function(ok, err)
        if ok then
          vim.notify("Queued: " .. item.name, vim.log.levels.INFO, { title = "NowPlaying.nvim" })
        else
          vim.notify("Queue failed: " .. (err or "unknown"), vim.log.levels.ERROR, { title = "NowPlaying.nvim" })
        end
      end)
    else
      client.play(item.uri, function(ok, err)
        if ok then
          vim.notify("Playing: " .. item.name, vim.log.levels.INFO, { title = "NowPlaying.nvim" })
        else
          vim.notify("Play failed: " .. (err or "unknown"), vim.log.levels.ERROR, { title = "NowPlaying.nvim" })
        end
      end)
    end
  elseif item.type == "album" then
    if action == "queue" then
      client.play(item.uri, function(ok, err)
        if ok then
          vim.notify("Playing album: " .. item.name, vim.log.levels.INFO, { title = "NowPlaying.nvim" })
        else
          vim.notify("Play failed: " .. (err or "unknown"), vim.log.levels.ERROR, { title = "NowPlaying.nvim" })
        end
      end)
    else
      client.album_tracks(item.id, function(tracks, err)
        if not tracks then
          vim.notify("Failed to load album: " .. (err or "unknown"), vim.log.levels.ERROR, { title = "NowPlaying.nvim" })
          return
        end
        for _, t in ipairs(tracks) do
          t.album = item.name
        end
        open_track_list(tracks, ICONS.album .. "  " .. item.name .. " \u{2014} " .. item.artist)
      end)
    end
  elseif item.type == "artist" then
    client.artist_top_tracks(item.id, function(tracks, err)
      if not tracks then
        vim.notify("Failed to load artist: " .. (err or "unknown"), vim.log.levels.ERROR, { title = "NowPlaying.nvim" })
        return
      end
      open_track_list(tracks, ICONS.artist .. "  " .. item.name .. " \u{2014} Top Tracks")
    end)
  elseif item.type == "playlist" then
    -- Drill down into playlist tracks
    client.playlist_tracks(item.id, function(tracks, err)
      if not tracks then
        vim.notify("Failed to load playlist: " .. (err or "unknown"), vim.log.levels.ERROR, { title = "NowPlaying.nvim" })
        return
      end
      open_track_list(tracks, ICONS.playlist .. "  " .. item.name)
    end)
  end
end

-- --------------------------------------------------------------------------
-- Main search picker
-- --------------------------------------------------------------------------

function M.open(opts)
  opts = opts or {}

  local has_telescope, _ = pcall(require, "telescope")
  if not has_telescope then
    vim.notify("telescope.nvim is required for Spotify search", vim.log.levels.ERROR, { title = "NowPlaying.nvim" })
    return
  end

  if not auth.is_authenticated() then
    vim.notify("Not authenticated. Run :NowPlayingSpotifyAuth first.", vim.log.levels.WARN, { title = "NowPlaying.nvim" })
    return
  end

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  setup_highlights()

  local cfg = config.get()
  local search_cfg = (cfg.spotify and cfg.spotify.search) or {}
  local debounce_ms = search_cfg.debounce_ms or 300
  local default_action = (cfg.spotify and cfg.spotify.actions and cfg.spotify.actions.default) or "play"

  local entry_maker = get_entry_maker()

  -- Debounce state
  local debounce_timer = nil
  local last_query = ""
  local is_loading = false
  local picker_ref = nil
  local prompt_bufnr_ref = nil

  local function refresh_with(items)
    if not picker_ref then return end
    if prompt_bufnr_ref and not vim.api.nvim_buf_is_valid(prompt_bufnr_ref) then return end
    picker_ref:refresh(finders.new_table({
      results = items,
      entry_maker = entry_maker,
    }), { reset_prompt = false })
  end

  local function show_loading()
    if not picker_ref then return end
    if prompt_bufnr_ref and not vim.api.nvim_buf_is_valid(prompt_bufnr_ref) then return end
    is_loading = true
    picker_ref:refresh(finders.new_table({
      results = { { type = "loading", name = "Searching..." } },
      entry_maker = function(item)
        if item.type == "loading" then
          return make_loading_entry()
        end
        return entry_maker(item)
      end,
    }), { reset_prompt = false })
  end

  pickers.new(opts, {
    prompt_title = ICONS.spotify .. " Spotify Search",
    results_title = "Results  " .. ICONS.play .. " <CR> Play/Browse  " .. ICONS.queue .. " <C-q> Queue",
    finder = finders.new_table({
      results = {},
      entry_maker = entry_maker,
    }),
    sorter = conf.generic_sorter({}),
    previewer = make_previewer(),
    layout_config = {
      horizontal = {
        preview_width = 0.4,
      },
      width = 0.85,
      height = 0.75,
    },
    attach_mappings = function(prompt_bufnr, map)
      prompt_bufnr_ref = prompt_bufnr
      picker_ref = action_state.get_current_picker(prompt_bufnr)

      -- Debounced search on each keystroke
      vim.api.nvim_buf_attach(prompt_bufnr, false, {
        on_lines = function()
          vim.schedule(function()
            if not vim.api.nvim_buf_is_valid(prompt_bufnr) then return end

            local lines = vim.api.nvim_buf_get_lines(prompt_bufnr, 0, 1, false)
            local prompt_text = lines[1] or ""
            local query = prompt_text:match("^.*>%s*(.*)$") or prompt_text

            if query == last_query then return end
            last_query = query

            if debounce_timer then
              debounce_timer:stop()
              debounce_timer:close()
              debounce_timer = nil
            end

            if query == "" then
              is_loading = false
              refresh_with({})
              return
            end

            -- Show loading state
            show_loading()

            local uv = vim.uv or vim.loop
            debounce_timer = uv.new_timer()
            debounce_timer:start(debounce_ms, 0, vim.schedule_wrap(function()
              if debounce_timer then
                debounce_timer:stop()
                debounce_timer:close()
                debounce_timer = nil
              end

              client.search(query, function(results, err)
                is_loading = false
                if err then
                  log.debug("Search error: " .. tostring(err))
                  return
                end
                if not results then return end
                if not vim.api.nvim_buf_is_valid(prompt_bufnr) then return end

                -- Flatten: tracks, then albums, then artists, then playlists
                local flat = {}
                for _, item in ipairs(results.tracks or {}) do table.insert(flat, item) end
                for _, item in ipairs(results.albums or {}) do table.insert(flat, item) end
                for _, item in ipairs(results.artists or {}) do table.insert(flat, item) end
                for _, item in ipairs(results.playlists or {}) do table.insert(flat, item) end

                refresh_with(flat)
              end)
            end))
          end)
        end,
      })

      -- Enter = play track / drill into album/artist
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        if not selection or not selection.value or selection.value.type == "loading" then
          return
        end
        actions.close(prompt_bufnr)
        handle_selection(selection.value, default_action)
      end)

      -- Ctrl-q = queue track
      local function queue_action()
        local selection = action_state.get_selected_entry()
        if not selection or not selection.value or selection.value.type == "loading" then
          return
        end
        if selection.value.type == "track" then
          actions.close(prompt_bufnr)
          handle_selection(selection.value, "queue")
        else
          vim.notify("Can only queue tracks", vim.log.levels.WARN, { title = "NowPlaying.nvim" })
        end
      end

      map("i", "<C-q>", queue_action)
      map("n", "<C-q>", queue_action)

      return true
    end,
  }):find()
end

return M
