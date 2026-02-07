local config = require("player.config")
local log = require("player.log")
local providers = require("player.providers")
local artwork = require("player.artwork")
local utils = require("player.utils")

local M = {
  current = { status = "inactive", track = nil, volume = nil, player = nil, artwork = nil },
}

local listeners = {}
local last_provider = nil

local function select_provider(preferred)
  if preferred and providers[preferred] then
    return providers[preferred]
  end

  local opts = config.get()
  for _, name in ipairs(opts.player_priority or {}) do
    local provider = providers[name]
    if provider and provider.is_available() then
      return provider
    end
  end

  return nil
end

local function emit(state)
  for _, cb in ipairs(listeners) do
    pcall(cb, state)
  end
end

function M.on_change(cb)
  table.insert(listeners, cb)
end

function M.refresh(opts)
  opts = opts or {}
  local provider = opts.provider or select_provider(last_provider)
  if not provider then
    M.current = { status = "inactive", player = nil, track = nil, volume = nil, artwork = nil }
    emit(M.current)
    return M.current, "no provider available"
  end

  local state_resp, err = provider.get_status()
  if not state_resp then
    log.debug(("get_status failed for %s: %s"):format(provider.name, err or "unknown error"))
    return nil, err
  end

  if state_resp.status == "inactive" and config.get().auto_switch then
    for _, name in ipairs(config.get().player_priority or {}) do
      if name ~= provider.name then
        local alt = providers[name]
        if alt and alt.is_available() then
          provider = alt
          state_resp, err = provider.get_status()
          if state_resp then
            break
          end
        end
      end
    end
  end

  state_resp.player = provider.name
  state_resp.player_label = utils.format_provider(provider.name)
  state_resp.artwork = artwork.fetch(provider, state_resp.track)
  M.current = state_resp
  last_provider = provider.name
  emit(M.current)
  return M.current
end

local function with_provider()
  local provider = select_provider(last_provider)
  if not provider then
    return nil, "no provider available"
  end
  return provider
end

function M.play_pause()
  local provider, err = with_provider()
  if not provider then
    return false, err
  end
  local ok, p_err = provider.play_pause()
  if ok then
    M.refresh({ provider = provider })
  end
  return ok, p_err
end

function M.next_track()
  local provider, err = with_provider()
  if not provider then
    return false, err
  end
  local ok, p_err = provider.next_track()
  if ok then
    M.refresh({ provider = provider })
  end
  return ok, p_err
end

function M.previous_track()
  local provider, err = with_provider()
  if not provider then
    return false, err
  end
  local ok, p_err = provider.previous_track()
  if ok then
    M.refresh({ provider = provider })
  end
  return ok, p_err
end

function M.stop()
  local provider, err = with_provider()
  if not provider then
    return false, err
  end
  if type(provider.stop) ~= "function" then
    return false, "stop not supported"
  end
  local ok, p_err = provider.stop()
  if ok then
    M.refresh({ provider = provider })
  end
  return ok, p_err
end

function M.seek(delta)
  local provider, err = with_provider()
  if not provider then
    return false, err
  end
  if type(provider.seek) ~= "function" then
    return false, "seek not supported"
  end
  local ok, p_err = provider.seek(delta)
  if ok then
    M.refresh({ provider = provider })
  end
  return ok, p_err
end

function M.volume_up()
  local provider, err = with_provider()
  if not provider then
    return false, err
  end
  local ok, _, p_err = provider.change_volume(5)
  if ok then
    M.refresh({ provider = provider })
  end
  return ok, p_err
end

function M.volume_down()
  local provider, err = with_provider()
  if not provider then
    return false, err
  end
  local ok, _, p_err = provider.change_volume(-5)
  if ok then
    M.refresh({ provider = provider })
  end
  return ok, p_err
end

function M.set_provider(name)
  last_provider = name
  return M.refresh({ provider = select_provider(name) })
end

function M.providers()
  local names = {}
  for name in pairs(providers) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

return M
