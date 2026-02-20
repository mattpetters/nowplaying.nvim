local log = require("player.log")
local utils = require("player.utils")

local M = {}

local TOKEN_FILE = "spotify_tokens.json"
local tokens = nil -- cached in memory

local function data_dir()
  local dir = vim.fn.stdpath("data") .. "/nowplaying.nvim"
  utils.ensure_dir(dir)
  return dir
end

local function token_path()
  return data_dir() .. "/" .. TOKEN_FILE
end

--- Read tokens from disk into memory cache
local function load_tokens()
  local path = token_path()
  if not utils.file_exists(path) then
    return nil
  end
  local fd = io.open(path, "r")
  if not fd then
    return nil
  end
  local content = fd:read("*a")
  fd:close()
  local ok, decoded = pcall(vim.json.decode, content)
  if not ok or type(decoded) ~= "table" then
    log.warn("Failed to decode Spotify token file")
    return nil
  end
  return decoded
end

--- Write tokens to disk and update memory cache
local function save_tokens(data)
  local path = token_path()
  local ok, encoded = pcall(vim.json.encode, data)
  if not ok then
    log.error("Failed to encode Spotify tokens")
    return false
  end
  local fd = io.open(path, "w")
  if not fd then
    log.error("Failed to write Spotify token file: " .. path)
    return false
  end
  fd:write(encoded)
  fd:close()
  tokens = data
  return true
end

--- Get the current tokens (from memory or disk)
function M.get()
  if tokens then
    return tokens
  end
  tokens = load_tokens()
  return tokens
end

--- Store new tokens received from Spotify OAuth
--- @param data table { access_token, refresh_token, expires_in, scope, token_type }
function M.store(data)
  local now = os.time()
  local to_save = {
    access_token = data.access_token,
    refresh_token = data.refresh_token or (tokens and tokens.refresh_token),
    expires_at = now + (tonumber(data.expires_in) or 3600) - 60, -- 60s buffer
    scope = data.scope,
    token_type = data.token_type or "Bearer",
    stored_at = now,
  }
  return save_tokens(to_save)
end

--- Check if the current access token is expired
function M.is_expired()
  local t = M.get()
  if not t or not t.expires_at then
    return true
  end
  return os.time() >= t.expires_at
end

--- Check if we have tokens at all
function M.has_tokens()
  local t = M.get()
  return t ~= nil and t.access_token ~= nil
end

--- Get the access token (nil if not available)
function M.access_token()
  local t = M.get()
  return t and t.access_token
end

--- Get the refresh token (nil if not available)
function M.refresh_token()
  local t = M.get()
  return t and t.refresh_token
end

--- Clear all stored tokens (logout)
function M.clear()
  tokens = nil
  local path = token_path()
  if utils.file_exists(path) then
    os.remove(path)
  end
end

return M
