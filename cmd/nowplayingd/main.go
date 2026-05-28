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
	"time"

	"github.com/mpetters/nowplaying/internal/audio"
	"github.com/mpetters/nowplaying/internal/daemon"
	"github.com/mpetters/nowplaying/internal/providers/spotify"
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

	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	d := daemon.New(daemon.Config{
		SocketPath: *socket,
		Logger:     logger,
	})
	// Register providers in priority order. The daemon auto-promotes
	// the first available provider and watches for changes (e.g. Spotify
	// launched after the daemon started).
	d.Register(spotify.New())
	d.Register(stub.New())
	logger.Info("registered providers", "active", d.ActiveProviderName())

	logger.Info("nowplayingd starting", "socket", *socket)
	go runSpectrum(ctx, d, logger)
	if err := d.Run(ctx); err != nil {
		fmt.Fprintln(os.Stderr, "nowplayingd:", err)
		os.Exit(1)
	}
}

func runSpectrum(ctx context.Context, d *daemon.Daemon, logger *slog.Logger) {
	cap := &audio.Capture{}
	if !cap.Available() {
		logger.Debug("audio capture not available on this platform")
		return
	}

	if err := cap.Start("com.spotify.client"); err != nil {
		logger.Warn("audio capture failed to start", "err", err)
		return
	}
	defer cap.Stop()
	logger.Info("audio capture started")

	const (
		fftSize    = 1024
		bands      = 16
		sampleRate = 44100
	)
	analyzer := audio.NewAnalyzer(fftSize, bands, sampleRate)
	buf := make([]float32, 4096)

	ticker := time.NewTicker(33 * time.Millisecond)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			n := cap.Read(buf)
			if n < fftSize {
				continue
			}
			window := buf[n-fftSize : n]
			bands := analyzer.Process(window)
			samples := make([]float64, fftSize)
			for i, s := range window {
				samples[i] = float64(s)
			}
			d.BroadcastSpectrum(bands, samples)
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
