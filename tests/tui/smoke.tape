# nowplaying TUI smoke tape.
#
# Run via `make tui-iterate` — the Makefile target boots a stub-provider
# daemon on $NP_SOCKET, sets it in the env, then hands this tape to vhs.
# The tape boots the TUI, captures the default theme, presses 't' to
# cycle to the matrix theme, captures that, then quits.
#
# Outputs:
#   tests/tui/out/default.png  — default theme frame
#   tests/tui/out/matrix.png   — matrix theme frame
#   tests/tui/out/smoke.gif    — full recording (handy for debugging)

Output "tests/tui/out/smoke.gif"

Set Shell "bash"
Set FontSize 16
Set Width 1200
Set Height 600
Set Padding 20
Set TypingSpeed 20ms

# Boot the TUI. NP_SOCKET is set by the make target.
Type "./bin/nowplaying -socket $NP_SOCKET -theme default"
Enter
Sleep 1500ms

Screenshot "tests/tui/out/default.png"

# Cycle to matrix theme.
Type "t"
Sleep 1200ms

Screenshot "tests/tui/out/matrix.png"

# Quit cleanly so vhs can finalize.
Type "q"
Sleep 300ms
