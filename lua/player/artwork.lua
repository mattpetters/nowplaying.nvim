local config = require("player.config")
local log = require("player.log")
local utils = require("player.utils")

local M = {}

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
  local dir = (((config.get().panel or {}).elements or {}).artwork or {}).cache_dir
  utils.ensure_dir(dir)
  return dir .. "/" .. slug .. ".jpg"
end

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
