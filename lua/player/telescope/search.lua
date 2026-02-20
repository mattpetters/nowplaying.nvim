local client = require("player.spotify_api.client")
local auth = require("player.spotify_api.auth")
local config = require("player.config")
local log = require("player.log")

local M = {}

-- Nerd Font icons
local ICONS = {
  track = "\u{f001}",  -- nf-fa-music
  album = "\u{f51f}",  -- nf-md-album
  artist = "\u{f0f3d}", -- nf-md-account_music
}

local TYPE_LABELS = {
  track = "Track",
  album = "Album",
  artist = "Artist",
}

--- Format duration from milliseconds to m:ss
local function format_duration(ms)
  if not ms then
    return ""
  end
  local total_sec = math.floor(ms / 1000)
  local min = math.floor(total_sec / 60)
  local sec = total_sec % 60
  return string.format("%d:%02d", min, sec)
end

--- Format a number with comma separators (e.g. 1234567 -> "1,234,567")
local function format_number(n)
  if not n or n == 0 then
    return "0"
  end
  local s = tostring(n)
  local result = ""
  local len = #s
  for i = 1, len do
    if i > 1 and (len - i + 1) % 3 == 0 then
      result = result .. ","
    end
    result = result .. s:sub(i, i)
  end
  return result
end

--- Build the display string for an entry
local function make_display(entry)
  local icon = ICONS[entry.value.type] or ""
  local label = TYPE_LABELS[entry.value.type] or ""
  local item = entry.value

  if item.type == "track" then
    local dur = format_duration(item.duration_ms)
    local parts = { icon, " ", item.name, " \u{2014} ", item.artist }
    if dur ~= "" then
      table.insert(parts, "  [" .. dur .. "]")
    end
    table.insert(parts, "  (" .. label .. ")")
    return table.concat(parts)
  elseif item.type == "album" then
    local parts = { icon, " ", item.name, " \u{2014} ", item.artist }
    if item.total_tracks then
      table.insert(parts, "  [" .. item.total_tracks .. " tracks]")
    end
    table.insert(parts, "  (" .. label .. ")")
    return table.concat(parts)
  elseif item.type == "artist" then
    local parts = { icon, " ", item.name }
    if item.genres and item.genres ~= "" then
      table.insert(parts, "  \u{2014} " .. item.genres)
    end
    table.insert(parts, "  (" .. label .. ")")
    return table.concat(parts)
  end

  return icon .. " " .. (item.name or "Unknown")
end

--- Build the ordinal for sorting (tracks first, then albums, then artists)
local function type_ordinal(item_type)
  if item_type == "track" then
    return 1
  elseif item_type == "album" then
    return 2
  elseif item_type == "artist" then
    return 3
  end
  return 4
end

--- Create an entry from a search result item
local function make_entry(item, idx)
  return {
    value = item,
    display = make_display,
    ordinal = string.format("%d_%03d_%s_%s",
      type_ordinal(item.type), idx, item.name or "", item.artist or ""),
  }
end

--- Flatten search results into a single sorted list
local function flatten_results(results)
  local entries = {}
  local idx = 0

  -- Tracks first
  for _, item in ipairs(results.tracks or {}) do
    idx = idx + 1
    table.insert(entries, make_entry(item, idx))
  end
  -- Then albums
  for _, item in ipairs(results.albums or {}) do
    idx = idx + 1
    table.insert(entries, make_entry(item, idx))
  end
  -- Then artists
  for _, item in ipairs(results.artists or {}) do
    idx = idx + 1
    table.insert(entries, make_entry(item, idx))
  end

  return entries
end

--- Open a track list picker (used for album/artist drill-down)
local function open_track_list(tracks, title)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local entries = {}
  for i, track in ipairs(tracks) do
    table.insert(entries, make_entry(track, i))
  end

  pickers.new({}, {
    prompt_title = title or "Spotify Tracks",
    finder = finders.new_table({
      results = entries,
      entry_maker = function(entry)
        return entry
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      -- Enter = play
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

      -- Ctrl-q = queue
      map("i", "<C-q>", function()
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
      end)

      map("n", "<C-q>", function()
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
      end)

      return true
    end,
    previewer = false,
  }):find()
end

--- Handle selection of a search result
local function handle_selection(item, action)
  if not item then
    return
  end

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
      -- Can't queue an album, play it as context instead
      client.play(item.uri, function(ok, err)
        if ok then
          vim.notify("Playing album: " .. item.name, vim.log.levels.INFO, { title = "NowPlaying.nvim" })
        else
          vim.notify("Play failed: " .. (err or "unknown"), vim.log.levels.ERROR, { title = "NowPlaying.nvim" })
        end
      end)
    else
      -- Drill down into album tracks
      client.album_tracks(item.id, function(tracks, err)
        if not tracks then
          vim.notify("Failed to load album: " .. (err or "unknown"), vim.log.levels.ERROR, { title = "NowPlaying.nvim" })
          return
        end
        -- Add album name to each track
        for _, t in ipairs(tracks) do
          t.album = item.name
        end
        open_track_list(tracks, ICONS.album .. "  " .. item.name .. " \u{2014} " .. item.artist)
      end)
    end
  elseif item.type == "artist" then
    -- Drill down into artist top tracks
    client.artist_top_tracks(item.id, function(tracks, err)
      if not tracks then
        vim.notify("Failed to load artist: " .. (err or "unknown"), vim.log.levels.ERROR, { title = "NowPlaying.nvim" })
        return
      end
      open_track_list(tracks, ICONS.artist .. "  " .. item.name .. " \u{2014} Top Tracks")
    end)
  end
end

-- --------------------------------------------------------------------------
-- Main search picker
-- --------------------------------------------------------------------------

function M.open(opts)
  opts = opts or {}

  -- Check dependencies
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

  local cfg = config.get()
  local search_cfg = (cfg.spotify and cfg.spotify.search) or {}
  local debounce_ms = search_cfg.debounce_ms or 300
  local default_action = (cfg.spotify and cfg.spotify.actions and cfg.spotify.actions.default) or "play"

  -- State for debounced dynamic search
  local current_results = {}
  local debounce_timer = nil
  local last_query = ""

  pickers.new(opts, {
    prompt_title = "\u{f1bc} Spotify Search",
    finder = finders.new_dynamic({
      fn = function(prompt)
        -- This gets called on each keystroke
        -- We do the actual API call via the entry_adder pattern below
        -- Return empty — we populate results asynchronously
        return current_results
      end,
      entry_maker = function(entry)
        return entry
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      local picker = action_state.get_current_picker(prompt_bufnr)

      -- Set up debounced search on prompt change
      vim.api.nvim_buf_attach(prompt_bufnr, false, {
        on_lines = function()
          vim.schedule(function()
            if not vim.api.nvim_buf_is_valid(prompt_bufnr) then
              return
            end
            local lines = vim.api.nvim_buf_get_lines(prompt_bufnr, 0, 1, false)
            local prompt_text = lines[1] or ""
            -- Strip the prompt prefix (telescope adds "> " or similar)
            -- The actual typed text comes after any prompt prefix
            local query = prompt_text:match("^.*>%s*(.*)$") or prompt_text

            if query == last_query then
              return
            end
            last_query = query

            -- Cancel pending timer
            if debounce_timer then
              debounce_timer:stop()
              debounce_timer:close()
              debounce_timer = nil
            end

            if query == "" then
              current_results = {}
              picker:refresh(finders.new_table({
                results = {},
                entry_maker = function(e)
                  return e
                end,
              }), { reset_prompt = false })
              return
            end

            local uv = vim.uv or vim.loop
            debounce_timer = uv.new_timer()
            debounce_timer:start(debounce_ms, 0, vim.schedule_wrap(function()
              if debounce_timer then
                debounce_timer:stop()
                debounce_timer:close()
                debounce_timer = nil
              end

              client.search(query, function(results, err)
                if err then
                  log.debug("Search error: " .. tostring(err))
                  return
                end
                if not results then
                  return
                end

                -- Check the picker is still alive
                if not vim.api.nvim_buf_is_valid(prompt_bufnr) then
                  return
                end

                current_results = flatten_results(results)
                picker:refresh(finders.new_table({
                  results = current_results,
                  entry_maker = function(e)
                    return e
                  end,
                }), { reset_prompt = false })
              end)
            end))
          end)
        end,
      })

      -- Enter = default action (play for tracks, drill-down for albums/artists)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if selection and selection.value then
          handle_selection(selection.value, default_action)
        end
      end)

      -- Ctrl-q = queue (for tracks)
      map("i", "<C-q>", function()
        local selection = action_state.get_selected_entry()
        if selection and selection.value then
          if selection.value.type == "track" then
            actions.close(prompt_bufnr)
            handle_selection(selection.value, "queue")
          else
            vim.notify("Can only queue tracks", vim.log.levels.WARN, { title = "NowPlaying.nvim" })
          end
        end
      end)

      map("n", "<C-q>", function()
        local selection = action_state.get_selected_entry()
        if selection and selection.value then
          if selection.value.type == "track" then
            actions.close(prompt_bufnr)
            handle_selection(selection.value, "queue")
          else
            vim.notify("Can only queue tracks", vim.log.levels.WARN, { title = "NowPlaying.nvim" })
          end
        end
      end)

      return true
    end,
    previewer = false,
  }):find()
end

return M
