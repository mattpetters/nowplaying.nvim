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
	"net"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

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

	ensureDaemon(*socket)

	model := tui.New(ctx, *socket, t)
	p := tea.NewProgram(model, tea.WithAltScreen(), tea.WithContext(ctx))
	if _, err := p.Run(); err != nil {
		fmt.Fprintln(os.Stderr, "nowplaying:", err)
		os.Exit(1)
	}
}

func ensureDaemon(socket string) {
	conn, err := net.DialTimeout("unix", socket, 500*time.Millisecond)
	if err == nil {
		conn.Close()
		return
	}

	bin, err := exec.LookPath("nowplayingd")
	if err != nil {
		self, _ := os.Executable()
		candidate := filepath.Join(filepath.Dir(self), "nowplayingd")
		if _, serr := os.Stat(candidate); serr == nil {
			bin = candidate
		}
	}
	if bin == "" {
		return
	}

	cmd := exec.Command(bin, "-socket", socket)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Stdout = nil
	cmd.Stderr = nil
	if cmd.Start() != nil {
		return
	}
	_ = cmd.Process.Release()

	for range 20 {
		time.Sleep(50 * time.Millisecond)
		c, err := net.DialTimeout("unix", socket, 100*time.Millisecond)
		if err == nil {
			c.Close()
			return
		}
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
