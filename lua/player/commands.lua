local config = require("player.config")
local notify_ui = require("player.ui.notify")
local panel = require("player.ui.panel")
local statusline = require("player.ui.statusline")
local state = require("player.state")

local M = {}

local registered = false
local poll_timer = nil
local ui_timer = nil
local marquee_timer = nil
local last_track_key = nil

local function track_key(snapshot)
  if not snapshot or snapshot.status == "inactive" then
    return "inactive"
  end
  local track = snapshot.track or {}
  return table.concat({
    snapshot.player or "",
    track.title or "",
    track.artist or "",
    track.album or "",
    tostring(track.duration or ""),
  }, "\031")
end

local function notify_error(msg)
  vim.notify(msg, vim.log.levels.ERROR, { title = "NowPlaying.nvim" })
end

local function wrap_action(fn)
  local ok, err = fn()
  if not ok then
    notify_error(err or "command failed")
    return
  end
end

local function refresh_and_notify()
  local snapshot, err = state.refresh()
  if not snapshot then
    notify_error(err or "unable to refresh player state")
    return
  end
  notify_ui.show(snapshot)
end

local function create_cmd(name, fn, opts)
  vim.api.nvim_create_user_command(name, fn, opts or {})
end

function M.setup()
  if registered then
    return
  end
  registered = true

  state.on_change(function(s)
    panel.update(s)
    local key = track_key(s)
    if key ~= last_track_key then
      last_track_key = key
      statusline.reset()
    end
    vim.cmd("redrawstatus")
  end)

  create_cmd("NowPlayingPlayPause", function()
    wrap_action(state.play_pause)
  end, { desc = "Toggle play/pause for the active player" })

  create_cmd("NowPlayingNext", function()
    wrap_action(state.next_track)
  end, { desc = "Skip to next track" })

  create_cmd("NowPlayingPrev", function()
    wrap_action(state.previous_track)
  end, { desc = "Go to previous track" })

  create_cmd("NowPlayingStop", function()
    wrap_action(state.stop)
  end, { desc = "Stop playback" })

  create_cmd("NowPlayingVolUp", function()
    wrap_action(state.volume_up)
  end, { desc = "Increase volume by 5%" })

  create_cmd("NowPlayingVolDown", function()
    wrap_action(state.volume_down)
  end, { desc = "Decrease volume by 5%" })

  create_cmd("NowPlayingTogglePanel", function()
    if panel.is_open and panel.is_open() then
      panel.toggle(state.current)
      return
    end
    local snapshot = state.refresh()
    panel.toggle(snapshot)
  end, { desc = "Toggle player panel" })

  create_cmd("NowPlayingNotify", function()
    refresh_and_notify()
  end, { desc = "Show current track via vim.notify" })

  create_cmd("NowPlayingRefresh", function()
    local snapshot, err = state.refresh()
    if not snapshot then
      notify_error(err or "unable to refresh player state")
      return
    end
  end, { desc = "Refresh player state" })

  create_cmd("NowPlayingSeekForward", function()
    wrap_action(function()
      return state.seek(5)
    end)
  end, { desc = "Seek forward 5 seconds" })

  create_cmd("NowPlayingSeekBackward", function()
    wrap_action(function()
      return state.seek(-5)
    end)
  end, { desc = "Seek backward 5 seconds" })

  local cfg = config.get()
  if cfg.poll and cfg.poll.enabled then
    if poll_timer then
      poll_timer:stop()
      poll_timer:close()
    end
    poll_timer = vim.loop.new_timer()
    poll_timer:start(0, cfg.poll.interval_ms, vim.schedule_wrap(function()
      state.refresh()
    end))
  end

  if ui_timer then
    ui_timer:stop()
    ui_timer:close()
  end
  ui_timer = vim.loop.new_timer()
  ui_timer:start(1000, 1000, vim.schedule_wrap(function()
    state.tick(1)
  end))

  if marquee_timer then
    marquee_timer:stop()
    marquee_timer:close()
  end
  local marquee_cfg = (cfg.statusline and cfg.statusline.marquee) or {}
  if marquee_cfg.enabled then
    local step_ms = tonumber(marquee_cfg.step_ms) or 140
    if step_ms > 0 then
      marquee_timer = vim.loop.new_timer()
      marquee_timer:start(step_ms, step_ms, vim.schedule_wrap(function()
        if statusline.tick() then
          vim.cmd("redrawstatus")
        end
      end))
    end
  end
end

return M
