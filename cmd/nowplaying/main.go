// nowplaying is the standalone TUI client for nowplayingd. It connects
// to the daemon over a Unix socket, subscribes to playback notifications,
// and renders a single now-playing pane themed via internal/theme.
//
// Phase 6 MVP: one pane, keyboard control (no mouse, no search).
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"

	tea "github.com/charmbracelet/bubbletea"

	"github.com/mpetters/nowplaying/cmd/nowplaying/tui"
	"github.com/mpetters/nowplaying/internal/theme"
)

func main() {
	socket := flag.String("socket", defaultSocketPath(), "daemon unix socket path")
	themeName := flag.String("theme", theme.DefaultName, "theme name (default, matrix)")
	flag.Parse()

	t, err := theme.Get(*themeName)
	if err != nil {
		fmt.Fprintln(os.Stderr, "nowplaying:", err)
		fmt.Fprintln(os.Stderr, "available themes:", theme.Names())
		os.Exit(2)
	}

	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	model := tui.New(ctx, *socket, t)
	p := tea.NewProgram(model, tea.WithAltScreen(), tea.WithContext(ctx))
	if _, err := p.Run(); err != nil {
		fmt.Fprintln(os.Stderr, "nowplaying:", err)
		os.Exit(1)
	}
}

func defaultSocketPath() string {
	if dir := os.Getenv("XDG_RUNTIME_DIR"); dir != "" {
		return filepath.Join(dir, "nowplaying.sock")
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "/tmp/nowplaying.sock"
	}
	return filepath.Join(home, ".cache", "nowplaying", "sock")
}
