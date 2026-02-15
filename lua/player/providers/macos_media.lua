-- macOS Global Now Playing provider
-- Uses nowplaying-cli (brew install nowplaying-cli) to read the system-wide
-- MediaRemote framework.  Works with ANY app: Spotify, Apple Music, YouTube
-- in any browser, VLC, IINA, podcasts, etc.
local utils = require("player.utils")

local M = {
  name = "macos_media",
  label = "Now Playing",
}

local CLI = "nowplaying-cli"

--- Run nowplaying-cli with arguments and return trimmed stdout.
---@param args string[]
---@return boolean ok
---@return string stdout
---@return string stderr
local function run_cli(args)
  local cmd = vim.list_extend({ CLI }, args)
  if type(vim.system) == "function" then
    local res = vim.system(cmd, { text = true }):wait()
    return res.code == 0, utils.trim(res.stdout or ""), utils.trim(res.stderr or "")
  end
  local output = vim.fn.system(cmd)
  local ok = vim.v.shell_error == 0
  return ok, utils.trim(output), ""
end

--- Parse the multi-line output of `nowplaying-cli get title artist album duration elapsedTime playbackRate`
--- Each requested field is printed on its own line.
---@param output string  raw stdout from nowplaying-cli
---@return table state   provider state table
function M._parse_output(output)
  if not output or output == "" then
    return { status = "inactive" }
  end

  local lines = vim.split(output, "\n", { plain = true })

  local title = lines[1] or "null"
  local artist = lines[2] or "null"
  local album = lines[3] or "null"
  local duration_raw = lines[4] or "null"
  local elapsed_raw = lines[5] or "null"
  local rate_raw = lines[6] or "null"

  -- "null" means the field is unavailable (nothing playing)
  if title == "null" and artist == "null" and duration_raw == "null" then
    return { status = "inactive" }
  end

  local duration = tonumber(duration_raw)
  local elapsed = tonumber(elapsed_raw)
  local rate = tonumber(rate_raw)

  -- Determine playback status from rate: 0 = paused, >0 = playing
  local status
  if rate and rate > 0 then
    status = "playing"
  else
    status = "paused"
  end

  return {
    status = status,
    track = {
      title = title ~= "null" and title or "Unknown",
      artist = artist ~= "null" and artist or "Unknown",
      album = album ~= "null" and album or "",
      duration = duration and math.floor(duration + 0.5) or nil,
    },
    position = elapsed and math.floor(elapsed + 0.5) or nil,
    volume = nil, -- MediaRemote doesn't expose system volume
  }
end

function M.is_available()
  return vim.fn.executable(CLI) == 1
end

function M.get_status()
  if not M.is_available() then
    return { status = "inactive" }, CLI .. " not found (brew install nowplaying-cli)"
  end

  local ok, stdout, stderr = run_cli({ "get", "title", "artist", "album", "duration", "elapsedTime", "playbackRate" })
  if not ok then
    return { status = "inactive" }, stderr ~= "" and stderr or "failed to query " .. CLI
  end

  return M._parse_output(stdout)
end

function M.play_pause()
  local ok, _, stderr = run_cli({ "togglePlayPause" })
  return ok, stderr
end

function M.next_track()
  local ok, _, stderr = run_cli({ "next" })
  return ok, stderr
end

function M.previous_track()
  local ok, _, stderr = run_cli({ "previous" })
  return ok, stderr
end

function M.stop()
  local ok, _, stderr = run_cli({ "pause" })
  return ok, stderr
end

function M.seek(delta)
  -- Get current position, add delta, seek to new position
  local ok, stdout = run_cli({ "get", "elapsedTime" })
  if not ok then
    return false, "failed to get current position"
  end
  local current = tonumber(utils.trim(stdout))
  if not current then
    return false, "no position available"
  end
  local target = math.max(0, current + delta)
  local sok, _, stderr = run_cli({ "seek", tostring(target) })
  return sok, stderr
end

function M.change_volume(_delta)
  -- MediaRemote doesn't expose volume control
  return false, "volume control not supported via system media"
end

function M.get_artwork(_, path)
  if not M.is_available() or not path then
    return false, "not available"
  end

  local ok, stdout = run_cli({ "get", "artworkData" })
  if not ok or not stdout or stdout == "" or stdout == "null" then
    return false, "no artwork available"
  end

  -- nowplaying-cli returns base64-encoded image data
  -- Decode and write to file
  local decoded
  if vim.base64 and vim.base64.decode then
    local dok, result = pcall(vim.base64.decode, stdout)
    if dok then
      decoded = result
    end
  end

  if not decoded then
    -- Fallback: use system base64 command
    local cmd = { "base64", "--decode" }
    if type(vim.system) == "function" then
      local res = vim.system(cmd, { text = false, stdin = stdout }):wait()
      if res.code == 0 and res.stdout then
        decoded = res.stdout
      end
    end
  end

  if not decoded or decoded == "" then
    return false, "failed to decode artwork"
  end

  -- Write decoded bytes to path
  local fh = io.open(path, "wb")
  if not fh then
    return false, "failed to open " .. path
  end
  fh:write(decoded)
  fh:close()

  return true, { path = path }
end

return M
