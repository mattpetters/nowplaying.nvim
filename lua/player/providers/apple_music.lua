local utils = require("player.utils")

local M = {
  name = "apple_music",
  label = "Music",
}

local running_script = [[tell application "System Events" to (name of processes) contains "Music"]]

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

  -- AppleScript may return numbers with comma as decimal separator depending on locale
  -- Replace commas with periods to ensure proper parsing
  local function parse_number(str)
    if not str then return nil end
    local normalized = str:gsub(",", ".")
    return tonumber(normalized)
  end

  local status = parts[4]
  local track = {
    title = parts[1],
    artist = parts[2],
    album = parts[3],
    duration = parse_number(parts[6]),
  }

  return {
    status = status,
    track = track,
    position = parse_number(parts[5]),
    volume = parse_number(parts[7]),
  }
end
M._parse_status = parse_status

function M.is_available()
  local ok, stdout = utils.run_osascript(running_script)
  return ok and stdout == "true"
end

function M.get_status()
  if not M.is_available() then
    return { status = "inactive" }, "Music is not running"
  end

  local script = [[
tell application "Music"
  if not (exists current track) then
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
    return nil, stderr ~= "" and stderr or "failed to query Music"
  end

  return parse_status(stdout)
end

function M.play_pause()
  local script = [[tell application "Music" to playpause]]
  local ok, _, stderr = utils.run_osascript(script)
  return ok, stderr
end

function M.next_track()
  local script = [[tell application "Music" to next track]]
  local ok, _, stderr = utils.run_osascript(script)
  return ok, stderr
end

function M.previous_track()
  local script = [[tell application "Music" to previous track]]
  local ok, _, stderr = utils.run_osascript(script)
  return ok, stderr
end

local function volume_script(delta)
  return string.format([[
tell application "Music"
  set newVolume to (sound volume) + (%d)
  if newVolume > 100 then
    set newVolume to 100
  end if
  if newVolume < 0 then
    set newVolume to 0
  end if
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
tell application "Music"
  if not (exists current track) then
    return "no-track"
  end if
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

local function artwork_script(path)
  return string.format([[
tell application "Music"
  if not (exists current track) then
    return "no-track"
  end if
  if not (exists artwork 1 of current track) then
    return "no-artwork"
  end if
  set artData to data of artwork 1 of current track
end tell

set outFile to POSIX file "%s"
try
  set fh to open for access outFile with write permission
  set eof of fh to 0
  write artData to fh
  close access fh
  return "%s"
on error errMsg
  try
    close access outFile
  end try
  error errMsg
end try
  ]], utils.escape_osa(path), utils.escape_osa(path))
end

function M.get_artwork(_, path)
  local ok, stdout, stderr = utils.run_osascript(artwork_script(path))
  if not ok then
    return false, stderr
  end
  if stdout == "no-artwork" or stdout == "no-track" then
    return false, stdout
  end
  return true, stdout
end

return M
