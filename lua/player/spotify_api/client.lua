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

--- Search Spotify for tracks, albums, and artists
--- @param query string The search query
--- @param callback function(results, err) where results = { tracks={}, albums={}, artists={} }
function M.search(query, callback)
  if not query or query == "" then
    callback({ tracks = {}, albums = {}, artists = {} })
    return
  end

  local cfg = config.get()
  local search_cfg = (cfg.spotify and cfg.spotify.search) or {}
  local limit = search_cfg.limit or 7

  local params = {
    q = query,
    type = "track,album,artist",
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
      }

      -- Parse tracks
      if data.tracks and data.tracks.items then
        for _, item in ipairs(data.tracks.items) do
          local artists = {}
          for _, a in ipairs(item.artists or {}) do
            table.insert(artists, a.name)
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

      -- Parse albums
      if data.albums and data.albums.items then
        for _, item in ipairs(data.albums.items) do
          local artists = {}
          for _, a in ipairs(item.artists or {}) do
            table.insert(artists, a.name)
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

      -- Parse artists
      if data.artists and data.artists.items then
        for _, item in ipairs(data.artists.items) do
          local genres = {}
          for i, g in ipairs(item.genres or {}) do
            if i <= 3 then
              table.insert(genres, g)
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

      callback(results)
    end,
  })
end

-- --------------------------------------------------------------------------
-- Playback control
-- --------------------------------------------------------------------------

--- Play a track, album, or artist URI on the active device
--- @param uri string Spotify URI (spotify:track:xxx, spotify:album:xxx, etc.)
--- @param callback function(ok, err)
function M.play(uri, callback)
  callback = callback or function() end

  local body = {}
  if uri:match("^spotify:track:") then
    body.uris = { uri }
  else
    -- album or artist context
    body.context_uri = uri
  end

  api_request("PUT", "/me/player/play", {
    body = body,
    callback = function(data, err)
      if err then
        callback(false, err)
        return
      end
      callback(true)
    end,
  })
end

--- Add a track to the queue
--- @param uri string Spotify track URI
--- @param callback function(ok, err)
function M.queue(uri, callback)
  callback = callback or function() end

  api_request("POST", "/me/player/queue", {
    params = { uri = uri },
    callback = function(data, err)
      if err then
        callback(false, err)
        return
      end
      callback(true)
    end,
  })
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

return M
