local config = require("player.config")
local log = require("player.log")
local utils = require("player.utils")

local M = {}

local function get_cache_dir()
  return (((config.get().panel or {}).elements or {}).artwork or {}).cache_dir
end

local function cache_path(provider_name, track)
  if not track or not track.title then
    return nil
  end
  local parts = {
    provider_name or "unknown",
    track.title or "untitled",
    track.artist or "",
    track.album or "",
  }
  local slug = utils.slug(table.concat(parts, "_"))
  local dir = get_cache_dir()
  utils.ensure_dir(dir)
  return dir .. "/" .. slug .. ".jpg"
end

--- Compute a cache file path for a given key string.
---@param cache_key string  identifier to slugify for filename
---@return string|nil  full path, or nil if key is nil/empty
function M.cache_path_for(cache_key)
  if not cache_key or cache_key == "" then
    return nil
  end
  local dir = get_cache_dir()
  utils.ensure_dir(dir)
  return dir .. "/" .. utils.slug(cache_key) .. ".jpg"
end

--- Fetch artwork by URL, using a slug-based cache.
--- Usable by both the panel UI and Telescope search previewer.
---@param url string  image URL (e.g. Spotify CDN)
---@param cache_key string  key for cache filename (will be slugified)
---@param callback? fun(result: table|nil)  if provided, fetch is async
---@return table|nil  { path = string } on sync success, nil on failure
function M.fetch_url(url, cache_key, callback)
  if not url or url == "" or not cache_key or cache_key == "" then
    return nil
  end

  local path = M.cache_path_for(cache_key)
  if not path then
    return nil
  end

  -- Return cached file immediately
  if utils.file_exists(path) then
    local result = { path = path }
    if callback then
      vim.schedule(function() callback(result) end)
    end
    return result
  end

  -- Async path
  if callback then
    local cmd = { "curl", "-L", "-s", "-o", path, url }
    vim.system(cmd, { text = true }, function(res)
      vim.schedule(function()
        if res.code == 0 then
          callback({ path = path })
        else
          log.warn(("artwork download failed for %s: %s"):format(url, res.stderr or "unknown"))
          callback(nil)
        end
      end)
    end)
    return nil -- async: no immediate result
  end

  -- Sync path
  local ok, err = utils.download(url, path)
  if ok then
    return { path = path }
  end
  log.warn(("artwork download failed for %s: %s"):format(url, tostring(err or "unknown")))
  return nil
end

--- Fetch artwork via a provider's get_artwork method (original API).
---@param provider table  provider with .name and .get_artwork(track, path)
---@param track table  track metadata
---@return table|nil  { path = string } or nil
function M.fetch(provider, track)
  if not provider or type(provider.get_artwork) ~= "function" then
    return nil
  end
  local path = cache_path(provider.name, track)
  if not path then
    return nil
  end
  if utils.file_exists(path) then
    return { path = path }
  end

  local ok, result = provider.get_artwork(track, path)
  if not ok then
    log.warn(("artwork fetch failed for %s: %s"):format(provider.name, tostring(result or "unknown")))
    return nil
  end
  if ok and result then
    if type(result) == "table" then
      if result.path then
        return result
      end
      local cfg = (((config.get().panel or {}).elements or {}).artwork) or {}
      if result.url and cfg.download then
        local ok_dl, err = utils.download(result.url, path)
        if ok_dl then
          return { path = path, from = "download" }
        end
        return { url = result.url, error = err }
      end
      return result
    end
    return { path = result }
  end
  log.warn(("artwork fetch returned nil for %s"):format(provider.name))
  return nil
end

return M
