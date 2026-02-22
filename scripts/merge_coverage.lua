-- scripts/merge_coverage.lua
-- Merge luacov.stats.child.*.out files into luacov.stats.out
-- Run via: nvim --headless -u NONE -l scripts/merge_coverage.lua
local project_root
local src = debug.getinfo(1, "S").source:sub(2)
if src and vim.fn.filereadable(src) == 1 then
  project_root = vim.fn.fnamemodify(src, ":p:h:h")
else
  project_root = vim.fn.getcwd()
end
local merged_file = project_root .. "/luacov.stats.out"

-- Find all child stats files
local child_files = vim.fn.glob(project_root .. "/luacov.stats.child.*.out", false, true)
if #child_files == 0 then
  print("No child coverage stats files found.")
  vim.cmd("qa!")
  return
end

-- Luacov stats format (per source file):
--   <max_lines>:<filepath>
--   <count1> <count2> <count3> ... (space-separated, one line)
-- Parse into { [filepath] = { max = N, hits = {count, count, ...} } }
local function parse_stats(path)
  local fh = io.open(path, "r")
  if not fh then return {} end
  local data = {}

  while true do
    local header = fh:read("*l")
    if not header then break end

    -- Header: <max_lines>:<filepath>
    local max_str, fname = header:match("^(%d+):(.+)$")
    if max_str and fname then
      local max_lines = tonumber(max_str)
      local counts_line = fh:read("*l") or ""
      local hits = {}
      for n in counts_line:gmatch("%S+") do
        table.insert(hits, tonumber(n) or 0)
      end
      data[fname] = { max = max_lines, hits = hits }
    end
  end

  fh:close()
  return data
end

-- Merge two stats tables
local function merge(base, other)
  for fname, odata in pairs(other) do
    if not base[fname] then
      base[fname] = odata
    else
      local bdata = base[fname]
      bdata.max = math.max(bdata.max, odata.max)
      for i, count in ipairs(odata.hits) do
        bdata.hits[i] = (bdata.hits[i] or 0) + count
      end
    end
  end
  return base
end

-- Write merged stats in luacov format
local function write_stats(data, path)
  local fh = io.open(path, "w")
  if not fh then
    print("Cannot write to " .. path)
    return
  end
  local fnames = {}
  for fname in pairs(data) do table.insert(fnames, fname) end
  table.sort(fnames)

  for _, fname in ipairs(fnames) do
    local d = data[fname]
    fh:write(d.max .. ":" .. fname .. "\n")
    local parts = {}
    for _, count in ipairs(d.hits) do
      table.insert(parts, tostring(count))
    end
    fh:write(table.concat(parts, " ") .. " \n")
  end
  fh:close()
end

-- Do the merge
local merged = {}

-- Include existing main stats if present (in case parent collected any)
local main_stat = io.open(merged_file, "r")
if main_stat then
  local size = main_stat:seek("end")
  main_stat:close()
  if size > 0 then
    merged = merge(merged, parse_stats(merged_file))
  end
end

for _, child_file in ipairs(child_files) do
  local child_data = parse_stats(child_file)
  merged = merge(merged, child_data)
  os.remove(child_file)
end

write_stats(merged, merged_file)

local file_count = 0
for _ in pairs(merged) do file_count = file_count + 1 end
print(string.format("Merged %d child stats files into %s (%d source files tracked)", #child_files, merged_file, file_count))

vim.cmd("qa!")
