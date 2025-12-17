local utils = require("player.utils")

local M = {
  name = "spotify",
  label = "Spotify",
}

local running_script = [[tell application "System Events" to (name of processes) contains "Spotify"]]

local function parse_number(value)
  if value == nil then
    return nil
  end
  local n = tonumber(value)
  if n then
    return n
  end
  -- handle locales that use comma as decimal separator
  local sanitized = tostring(value):gsub("%s+", "")
  sanitized = sanitized:gsub(",", ".")
  return tonumber(sanitized)
end

local function normalize_time_field(value)
  local n = parse_number(value)
  if not n then
    return nil
  end
  -- Spotify AppleScript reports duration in ms; some environments return seconds.
  if n > 60 * 60 * 10 then -- larger than 10 hours likely means ms
    n = n / 1000
  end
  return math.floor(n + 0.5)
end

local function parse_status(output)
  if output == "" then
    return nil, "empty response"
  end

  if output == "inactive" then
    return { status = "inactive" }
  end

  local parts = utils.split(output, "||")
  if #parts < 7 then
    return nil, "unexpected response: " .. output
  end

  local status = parts[4]
  local duration = normalize_time_field(parts[6])
  local position = normalize_time_field(parts[5])

  local track = {
    title = parts[1],
    artist = parts[2],
    album = parts[3],
    duration = duration,
  }

  return {
    status = status,
    track = track,
    position = position,
    volume = tonumber(parts[7]),
  }
end
M._parse_status = parse_status

function M.is_available()
  local ok, stdout = utils.run_osascript(running_script)
  return ok and stdout == "true"
end

function M.get_status()
  if not M.is_available() then
    return { status = "inactive" }, "Spotify is not running"
  end

  local script = [[
tell application "Spotify"
  if player state is stopped then
    return "inactive"
  end if

  set t to current track
  set track_name to name of t
  set artist_name to artist of t
  set album_name to album of t
  set player_state to player state as string
  set pos to player position
  set dur to duration of t
  set vol to sound volume

  return track_name & "||" & artist_name & "||" & album_name & "||" & player_state & "||" & pos & "||" & dur & "||" & vol
end tell
  ]]

  local ok, stdout, stderr = utils.run_osascript(script)
  if not ok then
    return nil, stderr ~= "" and stderr or "failed to query Spotify"
  end

  return parse_status(stdout)
end

function M.play_pause()
  local script = [[tell application "Spotify" to playpause]]
  local ok, _, stderr = utils.run_osascript(script)
  return ok, stderr
end

function M.next_track()
  local script = [[tell application "Spotify" to next track]]
  local ok, _, stderr = utils.run_osascript(script)
  return ok, stderr
end

function M.previous_track()
  local script = [[tell application "Spotify" to previous track]]
  local ok, _, stderr = utils.run_osascript(script)
  return ok, stderr
end

local function volume_script(delta)
  return string.format([[
tell application "Spotify"
  set newVolume to (sound volume) + (%d)
  if newVolume > 100 then set newVolume to 100
  if newVolume < 0 then set newVolume to 0
  set sound volume to newVolume
  return newVolume
end tell
  ]], delta)
end

function M.change_volume(delta)
  local ok, stdout, stderr = utils.run_osascript(volume_script(delta))
  return ok and tonumber(stdout), stderr
end

function M.seek(delta)
  local script = string.format([[
tell application "Spotify"
  set currentPos to player position
  set newPos to currentPos + (%d)
  if newPos < 0 then
    set newPos to 0
  end if
  set player position to newPos
  return newPos
end tell
  ]], delta)
  local ok, stdout, stderr = utils.run_osascript(script)
  if not ok then
    return false, stderr
  end
  return true, stdout
end

local function artwork_dump_script(path)
  return string.format([[
tell application "Spotify"
  if player state is stopped then return "no-track" end if
  if not (exists current track) then return "no-track" end if
  if not (exists artwork 1 of current track) then return "no-artwork" end if
  try
    set artData to raw data of artwork 1 of current track
  on error
    try
      set artData to data of artwork 1 of current track
    on error
      return "no-artwork"
    end try
  end try
  if artData is missing value then return "no-artwork" end if
end tell

set outFile to POSIX file "%s"
set fh to open for access outFile with write permission
set eof of fh to 0
write artData to fh
close access fh
return "%s"
  ]], utils.escape_osa(path), utils.escape_osa(path))
end

function M.get_artwork(_, path)
  local script = [[
tell application "Spotify"
  if player state is stopped then
    return "no-track"
  end if
  try
    return artwork url of current track as text
  on error errMsg number errNum
    return "no-artwork:" & errNum
  end try
end tell
  ]]

  local ok, stdout, stderr = utils.run_osascript(script)
  local trimmed = stdout or ""
  if not ok and trimmed == "" then
    trimmed = stderr ~= "" and stderr or "script-error"
  end

  if trimmed == "no-track" then
    return false, trimmed
  end

  -- If the AppleScript returns a URL, use it even if exit code was non-zero.
  if trimmed ~= "" and trimmed ~= "no-artwork" and trimmed ~= "script-error" then
    if trimmed:match("^https?://") then
      return true, { url = trimmed }
    end
  end

  -- Fallback: try extracting embedded artwork to disk if a path is available
  if path and path ~= "" then
    local ok_dump, dump_out, dump_err = utils.run_osascript(artwork_dump_script(path))
    if ok_dump and dump_out ~= "no-artwork" and dump_out ~= "no-track" then
      return true, { path = dump_out }
    end
    return false, dump_err ~= "" and dump_err or dump_out
  end

  return false, trimmed
end

return M
