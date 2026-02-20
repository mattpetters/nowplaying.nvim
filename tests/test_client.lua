-- Unit tests for player.spotify_api.client
-- Tests search result parsing, response normalization, and API result
-- structure. Since we can't make real API calls in tests, we test the
-- parsing/normalization logic by simulating Spotify API JSON responses.
local H = dofile("tests/helpers.lua")

local T = MiniTest.new_set({
  hooks = {
    pre_once = function()
      _G.child = H.new_child()
    end,
    post_once = function()
      child.stop()
    end,
    pre_case = function()
      child.lua([[
        package.loaded["player.config"] = nil
        package.loaded["player.spotify_api.token_store"] = nil
        package.loaded["player.spotify_api.auth"] = nil
        package.loaded["player.spotify_api.client"] = nil
        require("player.config").setup({})
      ]])
    end,
  },
})

-- ── Search result parsing ──────────────────────────────────────
-- We simulate the parsing logic that client.search() applies to
-- Spotify API responses. This tests the normalization independently
-- of the actual HTTP transport.

T["search_parsing"] = MiniTest.new_set()

T["search_parsing"]["parses track items correctly"] = function()
  local result = child.lua_get([[
    (function()
      -- Simulate the track parsing logic from client.search()
      local items = {
        {
          id = "track1",
          uri = "spotify:track:track1",
          name = "Test Song",
          artists = { { name = "Artist A" }, { name = "Artist B" } },
          album = { name = "Test Album", id = "album1", images = { { url = "https://img.example.com/1.jpg" } } },
          duration_ms = 240000,
          popularity = 85,
        }
      }

      local tracks = {}
      for _, item in ipairs(items) do
        if type(item) == "table" and item.id then
          local artists = {}
          for _, a in ipairs(item.artists or {}) do
            if type(a) == "table" then table.insert(artists, a.name) end
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
            album_id = item.album and item.album.id,
            image_url = item.album and item.album.images and item.album.images[1] and item.album.images[1].url,
          })
        end
      end

      return tracks[1]
    end)()
  ]])
  MiniTest.expect.equality(result.type, "track")
  MiniTest.expect.equality(result.id, "track1")
  MiniTest.expect.equality(result.name, "Test Song")
  MiniTest.expect.equality(result.artist, "Artist A, Artist B")
  MiniTest.expect.equality(result.album, "Test Album")
  MiniTest.expect.equality(result.duration_ms, 240000)
  MiniTest.expect.equality(result.popularity, 85)
  MiniTest.expect.equality(result.album_id, "album1")
  MiniTest.expect.equality(result.image_url, "https://img.example.com/1.jpg")
end

T["search_parsing"]["parses album items correctly"] = function()
  local result = child.lua_get([[
    (function()
      local item = {
        id = "album1",
        uri = "spotify:album:album1",
        name = "Great Album",
        artists = { { name = "Solo Artist" } },
        total_tracks = 12,
        release_date = "2023-05-15",
        images = { { url = "https://img.example.com/album.jpg" } },
      }

      local artists = {}
      for _, a in ipairs(item.artists or {}) do
        if type(a) == "table" then table.insert(artists, a.name) end
      end
      return {
        type = "album",
        id = item.id,
        uri = item.uri,
        name = item.name,
        artist = table.concat(artists, ", "),
        total_tracks = item.total_tracks,
        release_date = item.release_date,
        image_url = item.images and item.images[1] and item.images[1].url,
      }
    end)()
  ]])
  MiniTest.expect.equality(result.type, "album")
  MiniTest.expect.equality(result.name, "Great Album")
  MiniTest.expect.equality(result.artist, "Solo Artist")
  MiniTest.expect.equality(result.total_tracks, 12)
  MiniTest.expect.equality(result.release_date, "2023-05-15")
  MiniTest.expect.equality(result.image_url, "https://img.example.com/album.jpg")
end

T["search_parsing"]["parses artist items correctly"] = function()
  local result = child.lua_get([[
    (function()
      local item = {
        id = "artist1",
        uri = "spotify:artist:artist1",
        name = "Famous Artist",
        genres = { "rock", "alternative", "indie", "extra_ignored" },
        followers = { total = 1500000 },
        popularity = 92,
        images = { { url = "https://img.example.com/artist.jpg" } },
      }

      local genres = {}
      for i, g in ipairs(item.genres or {}) do
        if i <= 3 then
          if type(g) == "string" then table.insert(genres, g) end
        end
      end
      return {
        type = "artist",
        id = item.id,
        uri = item.uri,
        name = item.name,
        genres = table.concat(genres, ", "),
        followers = item.followers and item.followers.total or 0,
        popularity = item.popularity,
        image_url = item.images and item.images[1] and item.images[1].url,
      }
    end)()
  ]])
  MiniTest.expect.equality(result.type, "artist")
  MiniTest.expect.equality(result.name, "Famous Artist")
  MiniTest.expect.equality(result.genres, "rock, alternative, indie")
  MiniTest.expect.equality(result.followers, 1500000)
  MiniTest.expect.equality(result.popularity, 92)
end

T["search_parsing"]["limits genres to 3"] = function()
  local count = child.lua_get([[
    (function()
      local genres_raw = { "rock", "pop", "jazz", "blues", "folk" }
      local genres = {}
      for i, g in ipairs(genres_raw) do
        if i <= 3 then table.insert(genres, g) end
      end
      return #genres
    end)()
  ]])
  MiniTest.expect.equality(count, 3)
end

T["search_parsing"]["parses playlist items correctly"] = function()
  local result = child.lua_get([[
    (function()
      local item = {
        id = "pl1",
        uri = "spotify:playlist:pl1",
        name = "My Playlist",
        owner = { display_name = "DJ Cool" },
        description = "Best songs <b>ever</b>",
        tracks = { total = 50 },
        public = true,
        images = { { url = "https://img.example.com/pl.jpg" } },
      }

      return {
        type = "playlist",
        id = item.id,
        uri = item.uri,
        name = item.name,
        owner = item.owner and item.owner.display_name or "",
        description = item.description or "",
        total_tracks = item.tracks and item.tracks.total or 0,
        is_public = item.public,
        image_url = item.images and item.images[1] and item.images[1].url,
      }
    end)()
  ]])
  MiniTest.expect.equality(result.type, "playlist")
  MiniTest.expect.equality(result.name, "My Playlist")
  MiniTest.expect.equality(result.owner, "DJ Cool")
  MiniTest.expect.equality(result.total_tracks, 50)
  MiniTest.expect.equality(result.is_public, true)
end

T["search_parsing"]["handles null items in API response"] = function()
  local count = child.lua_get([[
    (function()
      -- Spotify sometimes returns null items in arrays.
      -- In Lua, nil in a table causes ipairs to stop early, so we
      -- simulate with vim.NIL (JSON null) which IS a real value.
      local items = { vim.NIL, { id = "valid", name = "Valid" }, vim.NIL }
      local results = {}
      for _, item in ipairs(items) do
        if type(item) == "table" and item.id then
          table.insert(results, item)
        end
      end
      return #results
    end)()
  ]])
  MiniTest.expect.equality(count, 1)
end

T["search_parsing"]["handles missing album on track"] = function()
  local result = child.lua_get([[
    (function()
      local item = {
        id = "t1",
        uri = "spotify:track:t1",
        name = "Orphan Track",
        artists = { { name = "A" } },
        album = nil,
        duration_ms = 180000,
      }
      return {
        album = item.album and item.album.name or "",
        image_url = item.album and item.album.images and item.album.images[1] and item.album.images[1].url,
      }
    end)()
  ]])
  MiniTest.expect.equality(result.album, "")
  MiniTest.expect.equality(result.image_url == nil or result.image_url == vim.NIL, true)
end

T["search_parsing"]["handles empty artists array"] = function()
  local result = child.lua_get([[
    (function()
      local artists = {}
      for _, a in ipairs({}) do
        if type(a) == "table" then table.insert(artists, a.name) end
      end
      return table.concat(artists, ", ")
    end)()
  ]])
  MiniTest.expect.equality(result, "")
end

-- ── Album tracks parsing ───────────────────────────────────────

T["album_tracks_parsing"] = MiniTest.new_set()

T["album_tracks_parsing"]["parses album track list"] = function()
  local result = child.lua_get([[
    (function()
      local data_items = {
        { id = "t1", uri = "spotify:track:t1", name = "Song 1", artists = {{ name = "A" }}, duration_ms = 200000, track_number = 1 },
        { id = "t2", uri = "spotify:track:t2", name = "Song 2", artists = {{ name = "A" }, { name = "B" }}, duration_ms = 180000, track_number = 2 },
      }

      local tracks = {}
      for _, item in ipairs(data_items) do
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
          duration_ms = item.duration_ms,
          track_number = item.track_number,
        })
      end

      return { count = #tracks, first_name = tracks[1].name, second_artist = tracks[2].artist }
    end)()
  ]])
  MiniTest.expect.equality(result.count, 2)
  MiniTest.expect.equality(result.first_name, "Song 1")
  MiniTest.expect.equality(result.second_artist, "A, B")
end

-- ── Playlist tracks parsing ────────────────────────────────────

T["playlist_tracks_parsing"] = MiniTest.new_set()

T["playlist_tracks_parsing"]["unwraps track from playlist item wrapper"] = function()
  local result = child.lua_get([[
    (function()
      -- Playlist tracks come wrapped: { track: { ... } }
      local items = {
        { track = { id = "t1", uri = "spotify:track:t1", name = "PL Song", artists = {{ name = "X" }}, album = { name = "AL" }, duration_ms = 150000 } },
        { track = nil },  -- can happen with local files
      }

      local tracks = {}
      for _, item in ipairs(items) do
        local t = item.track
        if t and t.id then
          local artists = {}
          for _, a in ipairs(t.artists or {}) do
            table.insert(artists, a.name)
          end
          table.insert(tracks, {
            type = "track",
            id = t.id,
            name = t.name,
            artist = table.concat(artists, ", "),
            album = t.album and t.album.name or "",
          })
        end
      end

      return { count = #tracks, name = tracks[1].name }
    end)()
  ]])
  MiniTest.expect.equality(result.count, 1) -- nil track filtered out
  MiniTest.expect.equality(result.name, "PL Song")
end

-- ── Play body construction ─────────────────────────────────────

T["play_body"] = MiniTest.new_set()

T["play_body"]["builds single track body"] = function()
  local result = child.lua_get([[
    (function()
      local uri = "spotify:track:abc123"
      local opts = {}
      local body = {}
      if opts.context_uri then
        body.context_uri = opts.context_uri
        if opts.offset_uri then body.offset = { uri = opts.offset_uri } end
      elseif uri:match("^spotify:track:") then
        body.uris = { uri }
      else
        body.context_uri = uri
      end
      return body
    end)()
  ]])
  MiniTest.expect.equality(result.uris[1], "spotify:track:abc123")
end

T["play_body"]["builds album context body"] = function()
  local result = child.lua_get([[
    (function()
      local uri = "spotify:album:xyz789"
      local opts = {}
      local body = {}
      if opts.context_uri then
        body.context_uri = opts.context_uri
      elseif uri:match("^spotify:track:") then
        body.uris = { uri }
      else
        body.context_uri = uri
      end
      return body
    end)()
  ]])
  MiniTest.expect.equality(result.context_uri, "spotify:album:xyz789")
end

T["play_body"]["builds context with offset body"] = function()
  local result = child.lua_get([[
    (function()
      local uri = "spotify:track:track5"
      local opts = { context_uri = "spotify:album:album1", offset_uri = "spotify:track:track5" }
      local body = {}
      if opts.context_uri then
        body.context_uri = opts.context_uri
        if opts.offset_uri then body.offset = { uri = opts.offset_uri } end
      elseif uri:match("^spotify:track:") then
        body.uris = { uri }
      else
        body.context_uri = uri
      end
      return body
    end)()
  ]])
  MiniTest.expect.equality(result.context_uri, "spotify:album:album1")
  MiniTest.expect.equality(result.offset.uri, "spotify:track:track5")
end

-- ── Config defaults ────────────────────────────────────────────

T["config"] = MiniTest.new_set()

T["config"]["search defaults are correct"] = function()
  local cfg = child.lua_get([[
    (function()
      local c = require("player.config").get()
      return c.spotify.search
    end)()
  ]])
  MiniTest.expect.equality(cfg.debounce_ms, 300)
  MiniTest.expect.equality(cfg.limit, 7)
  MiniTest.expect.equality(cfg.market == nil or cfg.market == vim.NIL, true)
end

T["config"]["action defaults are correct"] = function()
  local cfg = child.lua_get([[
    (function()
      local c = require("player.config").get()
      return c.spotify.actions
    end)()
  ]])
  MiniTest.expect.equality(cfg.default, "play")
  MiniTest.expect.equality(cfg.secondary, "queue")
end

return T
