local auth = require("player.spotify_api.auth")
local config = require("player.config")
local log = require("player.log")

local M = {}

local API_BASE = "https://api.spotify.com/v1"

-- --------------------------------------------------------------------------
-- Internal HTTP helpers
-- --------------------------------------------------------------------------

--- Make an authenticated async request to Spotify Web API
--- @param method string "GET"|"POST"|"PUT"|"DELETE"
--- @param endpoint string e.g. "/search" (appended to API_BASE)
--- @param opts table { params, body, callback }
local function api_request(method, endpoint, opts)
  opts = opts or {}
  local callback = opts.callback or function() end

  auth.ensure_token(function(token, err)
    if not token then
      callback(nil, err or "not authenticated")
      return
    end

    local url = API_BASE .. endpoint

    -- Append query params
    if opts.params then
      local parts = {}
      for k, v in pairs(opts.params) do
        local ek = tostring(k):gsub("([^%w%-%.%_%~])", function(c)
          return string.format("%%%02X", string.byte(c))
        end)
        local ev = tostring(v):gsub("([^%w%-%.%_%~])", function(c)
          return string.format("%%%02X", string.byte(c))
        end)
        table.insert(parts, ek .. "=" .. ev)
      end
      if #parts > 0 then
        url = url .. "?" .. table.concat(parts, "&")
      end
    end

    local cmd = {
      "curl", "-s",
      "-X", method,
      "-H", "Authorization: Bearer " .. token,
      "-H", "Content-Type: application/json",
    }

    if opts.body then
      local ok, json_body = pcall(vim.json.encode, opts.body)
      if ok then
        table.insert(cmd, "-d")
        table.insert(cmd, json_body)
      end
    end

    table.insert(cmd, url)

    vim.system(cmd, { text = true }, function(res)
      vim.schedule(function()
        if res.code ~= 0 then
          callback(nil, "HTTP request failed")
          return
        end

        local stdout = res.stdout or ""
        -- Some endpoints (PUT/DELETE) return empty body on success
        if stdout == "" then
          callback({})
          return
        end

        local ok, data = pcall(vim.json.decode, stdout)
        if not ok then
          callback(nil, "failed to parse response")
          return
        end

        -- Handle 401 — try token refresh and retry once
        if data.error and data.error.status == 401 then
          log.debug("Got 401, attempting token refresh...")
          auth.refresh_token(function(refresh_data, refresh_err)
            if not refresh_data then
              callback(nil, refresh_err or "token refresh failed")
              return
            end
            -- Retry the request with fresh token
            api_request(method, endpoint, opts)
          end)
          return
        end

        if data.error then
          local msg = data.error.message or "API error"
          log.debug("Spotify API error: " .. msg)
          callback(nil, msg)
          return
        end

        callback(data)
      end)
    end)
  end)
end

-- --------------------------------------------------------------------------
-- Search
-- --------------------------------------------------------------------------

--- Search Spotify for tracks, albums, artists, and playlists
--- @param query string The search query
--- @param callback function(results, err) where results = { tracks={}, albums={}, artists={}, playlists={} }
function M.search(query, callback)
  if not query or query == "" then
    callback({ tracks = {}, albums = {}, artists = {}, playlists = {} })
    return
  end

  local cfg = config.get()
  local search_cfg = (cfg.spotify and cfg.spotify.search) or {}
  local limit = search_cfg.limit or 7

  local params = {
    q = query,
    type = "track,album,artist,playlist",
    limit = limit,
  }

  local market = search_cfg.market
  if market and market ~= "" then
    params.market = market
  end

  api_request("GET", "/search", {
    params = params,
    callback = function(data, err)
      if not data then
        callback(nil, err)
        return
      end

      local results = {
        tracks = {},
        albums = {},
        artists = {},
        playlists = {},
      }

      -- Parse tracks
      if data.tracks and data.tracks.items then
        for _, item in ipairs(data.tracks.items) do
          if type(item) == "table" and item.id then
            local artists = {}
            for _, a in ipairs(item.artists or {}) do
              if type(a) == "table" then table.insert(artists, a.name) end
            end
            table.insert(results.tracks, {
              type = "track",
              id = item.id,
              uri = item.uri,
              name = item.name,
              artist = table.concat(artists, ", "),
              album = item.album and item.album.name or "",
              duration_ms = item.duration_ms,
              popularity = item.popularity,
              album_id = item.album and item.album.id,
              image_url = item.album and item.album.images and item.album.images[1] and item.album.images[1].url,
            })
          end
        end
      end

      -- Parse albums
      if data.albums and data.albums.items then
        for _, item in ipairs(data.albums.items) do
          if type(item) == "table" and item.id then
            local artists = {}
            for _, a in ipairs(item.artists or {}) do
              if type(a) == "table" then table.insert(artists, a.name) end
            end
            table.insert(results.albums, {
              type = "album",
              id = item.id,
              uri = item.uri,
              name = item.name,
              artist = table.concat(artists, ", "),
              total_tracks = item.total_tracks,
              release_date = item.release_date,
              image_url = item.images and item.images[1] and item.images[1].url,
            })
          end
        end
      end

      -- Parse artists
      if data.artists and data.artists.items then
        for _, item in ipairs(data.artists.items) do
          if type(item) == "table" and item.id then
            local genres = {}
            for i, g in ipairs(item.genres or {}) do
              if i <= 3 then
                if type(g) == "string" then table.insert(genres, g) end
              end
            end
            table.insert(results.artists, {
              type = "artist",
              id = item.id,
              uri = item.uri,
              name = item.name,
              genres = table.concat(genres, ", "),
              followers = item.followers and item.followers.total or 0,
              popularity = item.popularity,
              image_url = item.images and item.images[1] and item.images[1].url,
            })
          end
        end
      end

      -- Parse playlists
      if data.playlists and data.playlists.items then
        for _, item in ipairs(data.playlists.items) do
          if type(item) == "table" and item.id then
            table.insert(results.playlists, {
              type = "playlist",
              id = item.id,
              uri = item.uri,
              name = item.name,
              owner = item.owner and item.owner.display_name or "",
              description = item.description or "",
              total_tracks = item.tracks and item.tracks.total or 0,
              is_public = item.public,
              image_url = item.images and item.images[1] and item.images[1].url,
            })
          end
        end
      end

      callback(results)
    end,
  })
end

-- --------------------------------------------------------------------------
-- Device management
-- --------------------------------------------------------------------------

--- Get available Spotify Connect devices
--- @param callback function(devices, err) where devices is a list of device objects
function M.get_devices(callback)
  api_request("GET", "/me/player/devices", {
    callback = function(data, err)
      if not data then
        callback(nil, err)
        return
      end
      callback(data.devices or {})
    end,
  })
end

--- Try to activate a device if none is active, then retry the action
--- @param retry_fn function The function to retry after activation
--- @param callback function(ok, err)
local function ensure_device_then(retry_fn, callback)
  M.get_devices(function(devices, err)
    if not devices or #devices == 0 then
      callback(false, "No Spotify devices found. Open Spotify on a device first.")
      return
    end

    -- Find an active device, or pick the first available one
    local target = nil
    for _, d in ipairs(devices) do
      if type(d) == "table" then
        if d.is_active then
          -- There IS an active device — the original error was something else
          callback(false, "Playback failed despite active device. Try playing a song in Spotify first.")
          return
        end
        if not target then
          target = d
        end
      end
    end

    if not target then
      callback(false, "No Spotify devices available.")
      return
    end

    -- Transfer playback to the target device
    log.debug("Transferring playback to: " .. (target.name or "unknown device"))
    api_request("PUT", "/me/player", {
      body = { device_ids = { target.id }, play = false },
      callback = function(_, transfer_err)
        if transfer_err then
          callback(false, "Failed to activate device: " .. transfer_err)
          return
        end
        -- Small delay to let the transfer take effect, then retry
        vim.defer_fn(function()
          retry_fn(callback)
        end, 500)
      end,
    })
  end)
end

-- --------------------------------------------------------------------------
-- Playback control
-- --------------------------------------------------------------------------

--- Play a track, album, playlist, or artist URI on the active device.
--- Supports context_uri with offset to start an album/playlist at a specific track.
--- @param uri string Spotify URI (spotify:track:xxx, spotify:album:xxx, etc.)
--- @param opts table|nil Optional: { context_uri = "spotify:album:xxx", offset_uri = "spotify:track:xxx" }
--- @param callback function(ok, err)
function M.play(uri, opts, callback)
  -- Support (uri, callback) signature for backwards compat
  if type(opts) == "function" then
    callback = opts
    opts = nil
  end
  opts = opts or {}
  callback = callback or function() end

  local body = {}

  if opts.context_uri then
    -- Play a context (album/playlist) starting at a specific track
    body.context_uri = opts.context_uri
    if opts.offset_uri then
      body.offset = { uri = opts.offset_uri }
    end
  elseif uri:match("^spotify:track:") then
    body.uris = { uri }
  else
    -- album, artist, or playlist context
    body.context_uri = uri
  end

  local function do_play(cb)
    api_request("PUT", "/me/player/play", {
      body = body,
      callback = function(data, err)
        if err then
          -- Check if this is a "no active device" error
          if err:lower():match("no active device")
            or err:lower():match("player command failed")
            or err:lower():match("not found") then
            ensure_device_then(do_play, cb)
            return
          end
          cb(false, err)
          return
        end
        cb(true)
      end,
    })
  end

  do_play(callback)
end

--- Add a track to the queue
--- @param uri string Spotify track URI
--- @param callback function(ok, err)
function M.queue(uri, callback)
  callback = callback or function() end

  local function do_queue(cb)
    api_request("POST", "/me/player/queue", {
      params = { uri = uri },
      callback = function(data, err)
        if err then
          if err:lower():match("no active device")
            or err:lower():match("player command failed")
            or err:lower():match("not found") then
            ensure_device_then(do_queue, cb)
            return
          end
          cb(false, err)
          return
        end
        cb(true)
      end,
    })
  end

  do_queue(callback)
end

-- --------------------------------------------------------------------------
-- Drill-down helpers
-- --------------------------------------------------------------------------

--- Get tracks for an album
--- @param album_id string Spotify album ID
--- @param callback function(tracks, err)
function M.album_tracks(album_id, callback)
  api_request("GET", "/albums/" .. album_id .. "/tracks", {
    params = { limit = 50 },
    callback = function(data, err)
      if not data then
        callback(nil, err)
        return
      end

      local tracks = {}
      for _, item in ipairs(data.items or {}) do
        local artists = {}
        for _, a in ipairs(item.artists or {}) do
          table.insert(artists, a.name)
        end
        table.insert(tracks, {
          type = "track",
          id = item.id,
          uri = item.uri,
          name = item.name,
          artist = table.concat(artists, ", "),
          album = "", -- caller knows the album
          duration_ms = item.duration_ms,
          track_number = item.track_number,
        })
      end

      callback(tracks)
    end,
  })
end

--- Get top tracks for an artist
--- @param artist_id string Spotify artist ID
--- @param callback function(tracks, err)
function M.artist_top_tracks(artist_id, callback)
  local cfg = config.get()
  local market = (cfg.spotify and cfg.spotify.search and cfg.spotify.search.market) or "US"

  api_request("GET", "/artists/" .. artist_id .. "/top-tracks", {
    params = { market = market },
    callback = function(data, err)
      if not data then
        callback(nil, err)
        return
      end

      local tracks = {}
      for _, item in ipairs(data.tracks or {}) do
        local artists = {}
        for _, a in ipairs(item.artists or {}) do
          table.insert(artists, a.name)
        end
        table.insert(tracks, {
          type = "track",
          id = item.id,
          uri = item.uri,
          name = item.name,
          artist = table.concat(artists, ", "),
          album = item.album and item.album.name or "",
          duration_ms = item.duration_ms,
          popularity = item.popularity,
          image_url = item.album and item.album.images and item.album.images[1] and item.album.images[1].url,
        })
      end

      callback(tracks)
    end,
  })
end

--- Get tracks for a playlist
--- @param playlist_id string Spotify playlist ID
--- @param callback function(tracks, err)
function M.playlist_tracks(playlist_id, callback)
  api_request("GET", "/playlists/" .. playlist_id .. "/tracks", {
    params = { limit = 50, fields = "items(track(id,uri,name,artists,album(id,name,images),duration_ms,popularity))" },
    callback = function(data, err)
      if not data then
        callback(nil, err)
        return
      end

      local tracks = {}
      for _, item in ipairs(data.items or {}) do
        local t = item.track
        if t and t.id then
          local artists = {}
          for _, a in ipairs(t.artists or {}) do
            table.insert(artists, a.name)
          end
          table.insert(tracks, {
            type = "track",
            id = t.id,
            uri = t.uri,
            name = t.name,
            artist = table.concat(artists, ", "),
            album = t.album and t.album.name or "",
            duration_ms = t.duration_ms,
            popularity = t.popularity,
            image_url = t.album and t.album.images and t.album.images[1] and t.album.images[1].url,
          })
        end
      end

      callback(tracks)
    end,
  })
end

return M
