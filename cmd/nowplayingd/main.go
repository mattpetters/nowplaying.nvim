// nowplayingd is the shared daemon for the nowplaying TUI and Neovim
// plugin. It owns provider polling, transport commands, Spotify auth,
// and the artwork cache, and exposes a JSON-RPC protocol over a Unix
// domain socket.
package main

import (
	"context"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"

	"github.com/mpetters/nowplaying/internal/daemon"
	"github.com/mpetters/nowplaying/internal/providers/stub"
)

func main() {
	socket := flag.String("socket", defaultSocketPath(), "unix socket path")
	verbose := flag.Bool("v", false, "verbose logging")
	flag.Parse()

	level := slog.LevelInfo
	if *verbose {
		level = slog.LevelDebug
	}
	logger := slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: level}))

	d := daemon.New(daemon.Config{
		SocketPath: *socket,
		Logger:     logger,
	})
	d.Register(stub.New())

	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	logger.Info("nowplayingd starting", "socket", *socket)
	if err := d.Run(ctx); err != nil {
		fmt.Fprintln(os.Stderr, "nowplayingd:", err)
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
