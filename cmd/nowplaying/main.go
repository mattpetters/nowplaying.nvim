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
	daemonOnly := flag.Bool("daemon", false, "start nowplayingd and exit")
	debugDaemon := flag.Bool("debug", false, "with --daemon, run nowplayingd in the foreground with debug logging")
	flag.Parse()

	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	if *daemonOnly {
		if err := runDaemonCommand(ctx, *socket, *debugDaemon); err != nil {
			fmt.Fprintln(os.Stderr, "nowplaying:", err)
			os.Exit(1)
		}
		return
	}

	t, err := theme.Get(*themeName)
	if err != nil {
		fmt.Fprintln(os.Stderr, "nowplaying:", err)
		fmt.Fprintln(os.Stderr, "available themes:", theme.Names())
		os.Exit(2)
	}

	ensureDaemon(*socket)

	model := tui.New(ctx, *socket, t)
	p := tea.NewProgram(model, tea.WithAltScreen(), tea.WithContext(ctx))
	if _, err := p.Run(); err != nil {
		fmt.Fprintln(os.Stderr, "nowplaying:", err)
		os.Exit(1)
	}
}

func runDaemonCommand(ctx context.Context, socket string, debug bool) error {
	if daemonListening(socket) {
		if debug {
			return fmt.Errorf("daemon is already running on %s", socket)
		}
		return nil
	}

	bin := findDaemonBinary()
	if bin == "" {
		return fmt.Errorf("nowplayingd not found on PATH or next to this binary")
	}

	args := []string{"-socket", socket}
	if debug {
		args = append(args, "-v")
		cmd := exec.CommandContext(ctx, bin, args...)
		cmd.Stdin = os.Stdin
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		return cmd.Run()
	}

	cmd := exec.Command(bin, args...)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Stdout = nil
	cmd.Stderr = nil
	if err := cmd.Start(); err != nil {
		return err
	}
	if err := cmd.Process.Release(); err != nil {
		return err
	}

	for range 20 {
		time.Sleep(50 * time.Millisecond)
		if daemonListening(socket) {
			return nil
		}
	}
	return fmt.Errorf("daemon did not open %s", socket)
}

func ensureDaemon(socket string) {
	if daemonListening(socket) {
		return
	}

	bin := findDaemonBinary()
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
		if daemonListening(socket) {
			return
		}
	}
}

func daemonListening(socket string) bool {
	conn, err := net.DialTimeout("unix", socket, 500*time.Millisecond)
	if err != nil {
		return false
	}
	conn.Close()
	return true
}

func findDaemonBinary() string {
	bin, err := exec.LookPath("nowplayingd")
	if err == nil {
		return bin
	}

	self, _ := os.Executable()
	candidate := filepath.Join(filepath.Dir(self), "nowplayingd")
	if _, serr := os.Stat(candidate); serr == nil {
		return candidate
	}
	return ""
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
