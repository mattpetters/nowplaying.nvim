local M = {}

local has_vim_system = type(vim.system) == "function"

local function trim(str)
  return (str:gsub("^%s+", ""):gsub("%s+$", ""))
end

M.trim = trim

function M.split(str, sep)
  return vim.split(str, sep, { plain = true, trimempty = false })
end

function M.run_osascript(script)
  local cmd = { "osascript", "-e", script }

  if has_vim_system then
    local res = vim.system(cmd, { text = true }):wait()
    local ok = res.code == 0
    return ok, trim(res.stdout or ""), trim(res.stderr or "")
  end

  local output = vim.fn.system(cmd)
  local ok = vim.v.shell_error == 0
  return ok, trim(output), ""
end

function M.slug(str)
  local s = str:lower()
  s = s:gsub("%s+", "-")
  s = s:gsub("[^%w%-]", "")
  s = s:gsub("%-+", "-")
  return s
end

function M.ensure_dir(path)
  if path and path ~= "" then
    vim.fn.mkdir(path, "p")
  end
end

function M.file_exists(path)
  local stat = vim.loop.fs_stat(path)
  return stat and stat.type == "file"
end

function M.escape_osa(str)
  return (str or ""):gsub('"', '\\"')
end

function M.download(url, path)
  if not url or url == "" or not path then
    return false, "invalid url or path"
  end

  if vim.fn.executable("curl") ~= 1 then
    return false, "curl not available"
  end

  local cmd = { "curl", "-L", "-s", "-o", path, url }

  if has_vim_system then
    local res = vim.system(cmd, { text = true }):wait()
    return res.code == 0, res.stderr
  end

  local output = vim.fn.system(cmd)
  local ok = vim.v.shell_error == 0
  return ok, output
end

local provider_labels = {
  apple_music = " Apple Music",
  spotify = " Spotify",
  macos_media = "󰎆 Now Playing",
}

function M.format_provider(name)
  if not name or name == "" then
    return "player"
  end
  if provider_labels[name] then
    return provider_labels[name]
  end
  -- Fallback: capitalize words separated by underscores
  local cleaned = name:gsub("_", " ")
  return (cleaned:gsub("(%a)([%w']*)", function(first, rest)
    return first:upper() .. rest
  end))
end

return M
