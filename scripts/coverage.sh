#!/usr/bin/env bash
# scripts/coverage.sh — Generate coverage report and badge from luacov stats.
# Usage: ./scripts/coverage.sh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

STATS_FILE="luacov.stats.out"
REPORT_FILE="luacov.report.out"
BADGE_FILE="assets/coverage-badge.svg"

LUAROCKS_SHARE="$HOME/.luarocks/share/lua/5.1"

if [ ! -f "$STATS_FILE" ]; then
  echo "No coverage stats found. Run 'make coverage' first."
  exit 1
fi

# Generate the text report using luacov CLI
LUA_PATH="$LUAROCKS_SHARE/?.lua;$LUAROCKS_SHARE/?/init.lua;;" \
  lua5.1 -e "
    package.path = '$LUAROCKS_SHARE/?.lua;$LUAROCKS_SHARE/?/init.lua;' .. package.path
    local runner = require('luacov.runner')
    local configuration = require('luacov.defaults')
    configuration.statsfile = '$STATS_FILE'
    configuration.reportfile = '$REPORT_FILE'
    configuration.include = { 'player/' }
    configuration.exclude = { 'tests/', 'scripts/', 'deps/', 'mini%%%.', 'telescope%%%.', 'image%%%.', 'luacov' }
    local reporter = require('luacov.reporter.default')
    reporter.report()
  " 2>/dev/null || {
  # Fallback: try with nvim's built-in LuaJIT
  nvim --headless -u NONE -c "lua (function()
    package.path = '$LUAROCKS_SHARE/?.lua;$LUAROCKS_SHARE/?/init.lua;' .. package.path
    local ok, reporter = pcall(require, 'luacov.reporter.default')
    if ok then
      local defaults = require('luacov.defaults')
      defaults.statsfile = '$STATS_FILE'
      defaults.reportfile = '$REPORT_FILE'
      defaults.include = { 'player/' }
      defaults.exclude = { 'tests/', 'scripts/', 'deps/', 'mini%%.', 'telescope%%.', 'image%%.', 'luacov' }
      reporter.report()
    else
      print('luacov reporter not available')
    end
  end)()" -c "qa!" 2>/dev/null
}

if [ ! -f "$REPORT_FILE" ]; then
  echo "Failed to generate coverage report."
  exit 1
fi

# Parse the summary line from the report.
# The last section looks like:
# Total        1234    567    46.00%
SUMMARY_LINE=$(grep '^Total' "$REPORT_FILE" | tail -1)
if [ -z "$SUMMARY_LINE" ]; then
  echo "Could not find summary in coverage report."
  cat "$REPORT_FILE"
  exit 1
fi

PERCENT=$(echo "$SUMMARY_LINE" | awk '{print $NF}' | tr -d '%')
echo "Coverage: ${PERCENT}%"

# Determine badge color based on coverage percentage
if (( $(echo "$PERCENT >= 80" | bc -l) )); then
  COLOR="#4c1"       # green
  COLOR_NAME="brightgreen"
elif (( $(echo "$PERCENT >= 60" | bc -l) )); then
  COLOR="#a3c51c"    # yellow-green
  COLOR_NAME="yellowgreen"
elif (( $(echo "$PERCENT >= 40" | bc -l) )); then
  COLOR="#dfb317"    # yellow
  COLOR_NAME="yellow"
else
  COLOR="#e05d44"    # red
  COLOR_NAME="red"
fi

# Generate SVG badge (shields.io style)
mkdir -p "$(dirname "$BADGE_FILE")"
cat > "$BADGE_FILE" <<SVGEOF
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="116" height="20" role="img" aria-label="coverage: ${PERCENT}%">
  <title>coverage: ${PERCENT}%</title>
  <linearGradient id="s" x2="0" y2="100%">
    <stop offset="0" stop-color="#bbb" stop-opacity=".1"/>
    <stop offset="1" stop-opacity=".1"/>
  </linearGradient>
  <clipPath id="r">
    <rect width="116" height="20" rx="3" fill="#fff"/>
  </clipPath>
  <g clip-path="url(#r)">
    <rect width="63" height="20" fill="#555"/>
    <rect x="63" width="53" height="20" fill="${COLOR}"/>
    <rect width="116" height="20" fill="url(#s)"/>
  </g>
  <g fill="#fff" text-anchor="middle" font-family="Verdana,Geneva,DejaVu Sans,sans-serif" text-rendering="geometricPrecision" font-size="110">
    <text aria-hidden="true" x="325" y="150" fill="#010101" fill-opacity=".3" transform="scale(.1)" textLength="530">coverage</text>
    <text x="325" y="140" transform="scale(.1)" fill="#fff" textLength="530">coverage</text>
    <text aria-hidden="true" x="885" y="150" fill="#010101" fill-opacity=".3" transform="scale(.1)" textLength="430">${PERCENT}%</text>
    <text x="885" y="140" transform="scale(.1)" fill="#fff" textLength="430">${PERCENT}%</text>
  </g>
</svg>
SVGEOF

echo "Badge generated: $BADGE_FILE"
echo "Report: $REPORT_FILE"
