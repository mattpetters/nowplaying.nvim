local config = require("player.config")
local log = require("player.log")
local token_store = require("player.spotify_api.token_store")

local M = {}

local REDIRECT_PORT = 48721
local REDIRECT_URI = "http://127.0.0.1:" .. REDIRECT_PORT .. "/callback"
local AUTH_URL = "https://accounts.spotify.com/authorize"
local TOKEN_URL = "https://accounts.spotify.com/api/token"
local SCOPES = "user-read-playback-state user-modify-playback-state"

local DEFAULT_CLIENT_ID = "52fa8f0460d447ae89737c655891a18a"

local function get_client_id()
  local cfg = config.get()
  local id = cfg.spotify and cfg.spotify.client_id
  if id and id ~= "" then
    return id
  end
  return DEFAULT_CLIENT_ID
end

-- --------------------------------------------------------------------------
-- PKCE helpers
-- --------------------------------------------------------------------------

--- Generate a random string of given length using URL-safe base64 chars
local function random_string(length)
  local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
  local result = {}
  -- seed from urandom if available, fallback to os.time
  local fd = io.open("/dev/urandom", "rb")
  if fd then
    local bytes = fd:read(length)
    fd:close()
    for i = 1, length do
      local byte = string.byte(bytes, i)
      result[i] = chars:sub((byte % #chars) + 1, (byte % #chars) + 1)
    end
  else
    math.randomseed(os.time() + os.clock() * 1000)
    for i = 1, length do
      local idx = math.random(1, #chars)
      result[i] = chars:sub(idx, idx)
    end
  end
  return table.concat(result)
end

--- Base64url encode (no padding, URL-safe)
local function base64url_encode(data)
  -- Use openssl to base64 encode, then convert to url-safe
  local cmd = { "openssl", "base64", "-A" }
  local res = vim.system(cmd, { stdin = data, text = true }):wait()
  if res.code ~= 0 then
    return nil, "base64 encoding failed"
  end
  local encoded = res.stdout or ""
  -- Make URL-safe: replace + with -, / with _, strip =
  encoded = encoded:gsub("%+", "-"):gsub("/", "_"):gsub("=", "")
  return encoded
end

--- SHA256 hash of a string (raw bytes)
local function sha256(input)
  local cmd = { "openssl", "dgst", "-sha256", "-binary" }
  local res = vim.system(cmd, { stdin = input, text = false }):wait()
  if res.code ~= 0 then
    return nil, "SHA256 failed"
  end
  return res.stdout
end

--- Generate PKCE code verifier and challenge
local function generate_pkce()
  local verifier = random_string(128)
  local hash, err = sha256(verifier)
  if not hash then
    return nil, nil, err
  end
  local challenge, b_err = base64url_encode(hash)
  if not challenge then
    return nil, nil, b_err
  end
  return verifier, challenge
end

--- URL-encode a string
local function url_encode(str)
  return str:gsub("([^%w%-%.%_%~])", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
end

--- Build query string from table
local function build_query(params)
  local parts = {}
  -- sort keys for deterministic output
  local keys = vim.tbl_keys(params)
  table.sort(keys)
  for _, k in ipairs(keys) do
    table.insert(parts, url_encode(k) .. "=" .. url_encode(tostring(params[k])))
  end
  return table.concat(parts, "&")
end

-- --------------------------------------------------------------------------
-- Local HTTP callback server (via vim.uv TCP)
-- --------------------------------------------------------------------------

local function parse_http_request(data)
  local method, path = data:match("^(%w+)%s+(/[^%s]*)%s+HTTP")
  if not method or not path then
    return nil
  end
  -- Parse query params from path
  local base_path, query_string = path:match("^([^?]+)%??(.*)")
  local params = {}
  if query_string and query_string ~= "" then
    for pair in query_string:gmatch("[^&]+") do
      local key, value = pair:match("^([^=]+)=?(.*)")
      if key then
        params[key] = value or ""
      end
    end
  end
  return { method = method, path = base_path, params = params }
end

local function http_response(status, body, content_type)
  content_type = content_type or "text/html"
  return table.concat({
    "HTTP/1.1 " .. status,
    "Content-Type: " .. content_type,
    "Content-Length: " .. #body,
    "Connection: close",
    "",
    body,
  }, "\r\n")
end

local SUCCESS_HTML = [[
<!DOCTYPE html>
<html>
<head><title>NowPlaying.nvim</title>
<style>
  body { font-family: -apple-system, system-ui, sans-serif; display: flex;
         justify-content: center; align-items: center; min-height: 100vh;
         margin: 0; background: #121212; color: #fff; }
  .card { text-align: center; padding: 2rem; }
  h1 { color: #1DB954; margin-bottom: 0.5rem; }
  p { color: #b3b3b3; }
</style></head>
<body>
  <div class="card">
    <h1>Authenticated</h1>
    <p>You can close this tab and return to Neovim.</p>
  </div>
</body>
</html>
]]

local ERROR_HTML = [[
<!DOCTYPE html>
<html>
<head><title>NowPlaying.nvim - Error</title>
<style>
  body { font-family: -apple-system, system-ui, sans-serif; display: flex;
         justify-content: center; align-items: center; min-height: 100vh;
         margin: 0; background: #121212; color: #fff; }
  .card { text-align: center; padding: 2rem; }
  h1 { color: #e74c3c; }
  p { color: #b3b3b3; }
</style></head>
<body>
  <div class="card">
    <h1>Authentication Failed</h1>
    <p>%s</p>
    <p>Please try again from Neovim with <code>:NowPlayingSpotifyAuth</code></p>
  </div>
</body>
</html>
]]

--- Exchange authorization code for tokens
local function exchange_code(code, verifier, callback)
  local body = build_query({
    grant_type = "authorization_code",
    code = code,
    redirect_uri = REDIRECT_URI,
    client_id = get_client_id(),
    code_verifier = verifier,
  })

  local cmd = {
    "curl", "-s", "-X", "POST", TOKEN_URL,
    "-H", "Content-Type: application/x-www-form-urlencoded",
    "-d", body,
  }

  vim.system(cmd, { text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        callback(nil, "token exchange request failed")
        return
      end
      local ok, data = pcall(vim.json.decode, res.stdout)
      if not ok or not data then
        callback(nil, "failed to parse token response")
        return
      end
      if data.error then
        callback(nil, data.error_description or data.error)
        return
      end
      callback(data)
    end)
  end)
end

--- Refresh an expired access token
function M.refresh_token(callback)
  local rt = token_store.refresh_token()
  if not rt then
    if callback then
      callback(nil, "no refresh token available")
    end
    return
  end

  local body = build_query({
    grant_type = "refresh_token",
    refresh_token = rt,
    client_id = get_client_id(),
  })

  local cmd = {
    "curl", "-s", "-X", "POST", TOKEN_URL,
    "-H", "Content-Type: application/x-www-form-urlencoded",
    "-d", body,
  }

  vim.system(cmd, { text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        if callback then
          callback(nil, "refresh request failed")
        end
        return
      end
      local ok, data = pcall(vim.json.decode, res.stdout)
      if not ok or not data then
        if callback then
          callback(nil, "failed to parse refresh response")
        end
        return
      end
      if data.error then
        if callback then
          callback(nil, data.error_description or data.error)
        end
        return
      end
      token_store.store(data)
      if callback then
        callback(data)
      end
    end)
  end)
end

--- Ensure we have a valid access token, refreshing if needed
--- Calls callback(access_token) or callback(nil, err)
function M.ensure_token(callback)
  if not token_store.has_tokens() then
    callback(nil, "not authenticated — run :NowPlayingSpotifyAuth")
    return
  end

  if not token_store.is_expired() then
    callback(token_store.access_token())
    return
  end

  -- Token expired, try refresh
  M.refresh_token(function(data, err)
    if not data then
      callback(nil, err or "token refresh failed")
      return
    end
    callback(token_store.access_token())
  end)
end

--- Start the PKCE OAuth flow: open browser + listen for callback
function M.login()
  local client_id = get_client_id()
  if not client_id or client_id == "" then
    log.error("Spotify client_id not configured. Set spotify.client_id in your NowPlaying config.")
    return
  end

  local verifier, challenge, err = generate_pkce()
  if not verifier then
    log.error("Failed to generate PKCE challenge: " .. (err or "unknown"))
    return
  end

  local state = random_string(32)

  -- Build authorization URL
  local auth_params = build_query({
    client_id = client_id,
    response_type = "code",
    redirect_uri = REDIRECT_URI,
    scope = SCOPES,
    code_challenge_method = "S256",
    code_challenge = challenge,
    state = state,
  })
  local auth_url = AUTH_URL .. "?" .. auth_params

  -- Start local server to receive the callback
  local uv = vim.uv or vim.loop
  local server = uv.new_tcp()

  local ok_bind, bind_err = pcall(function()
    server:bind("127.0.0.1", REDIRECT_PORT)
  end)
  if not ok_bind then
    log.error("Failed to bind callback server on port " .. REDIRECT_PORT .. ": " .. tostring(bind_err))
    server:close()
    return
  end

  -- Auto-close after 120 seconds
  local timeout = uv.new_timer()
  local function cleanup()
    if timeout then
      pcall(function()
        timeout:stop()
        timeout:close()
      end)
      timeout = nil
    end
    if server then
      pcall(function()
        server:close()
      end)
      server = nil
    end
  end

  timeout:start(120000, 0, vim.schedule_wrap(function()
    log.warn("Spotify auth timed out (120s)")
    cleanup()
  end))

  server:listen(1, function(listen_err)
    if listen_err then
      vim.schedule(function()
        log.error("Callback server listen error: " .. tostring(listen_err))
      end)
      cleanup()
      return
    end

    local client = uv.new_tcp()
    server:accept(client)

    local buf = ""
    client:read_start(function(read_err, data)
      if read_err or not data then
        client:close()
        cleanup()
        return
      end

      buf = buf .. data

      -- Wait for full HTTP headers
      if not buf:find("\r\n\r\n") then
        return
      end

      local req = parse_http_request(buf)
      if not req or req.path ~= "/callback" then
        local resp = http_response("404 Not Found", "Not found")
        client:write(resp, function()
          client:close()
        end)
        return
      end

      -- Verify state matches
      if req.params.state ~= state then
        local resp = http_response("400 Bad Request", string.format(ERROR_HTML, "State mismatch — possible CSRF attack."))
        client:write(resp, function()
          client:close()
          cleanup()
        end)
        return
      end

      -- Check for error
      if req.params.error then
        local msg = req.params.error_description or req.params.error
        local resp = http_response("400 Bad Request", string.format(ERROR_HTML, msg))
        client:write(resp, function()
          client:close()
          cleanup()
        end)
        vim.schedule(function()
          log.error("Spotify auth error: " .. msg)
        end)
        return
      end

      -- Got the code — exchange it
      local code = req.params.code
      if not code then
        local resp = http_response("400 Bad Request", string.format(ERROR_HTML, "No authorization code received."))
        client:write(resp, function()
          client:close()
          cleanup()
        end)
        return
      end

      -- Send success page immediately
      local resp = http_response("200 OK", SUCCESS_HTML)
      client:write(resp, function()
        client:close()
        cleanup()
      end)

      -- Exchange code for tokens (async)
      vim.schedule(function()
        exchange_code(code, verifier, function(token_data, token_err)
          if not token_data then
            log.error("Token exchange failed: " .. (token_err or "unknown error"))
            return
          end
          token_store.store(token_data)
          log.info("Spotify authentication successful!")
          vim.notify("Spotify authenticated successfully!", vim.log.levels.INFO, { title = "NowPlaying.nvim" })
        end)
      end)
    end)
  end)

  -- Open browser
  local open_cmd
  if vim.fn.has("mac") == 1 then
    open_cmd = { "open", auth_url }
  elseif vim.fn.has("unix") == 1 then
    open_cmd = { "xdg-open", auth_url }
  else
    open_cmd = { "cmd", "/c", "start", auth_url }
  end

  vim.system(open_cmd, {}, function() end)
  log.info("Opening browser for Spotify authentication...")
  vim.notify("Opening browser for Spotify login...", vim.log.levels.INFO, { title = "NowPlaying.nvim" })
end

--- Check if the user is currently authenticated
function M.is_authenticated()
  return token_store.has_tokens()
end

--- Logout — clear stored tokens
function M.logout()
  token_store.clear()
  log.info("Spotify tokens cleared")
end

return M
