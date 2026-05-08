// Package fakeserver is a deterministic, in-process JSON-RPC server used
// by TUI tests. It speaks the same wire protocol as the real daemon
// (see internal/proto and internal/ipc) but its state is fully controlled
// by the test: SetState publishes a PlayerState that the next state.get
// call will return, and Push fires a notification to subscribed clients.
//
// It deliberately reuses ipc.NewServer so the TUI's connect/subscribe/
// state.get path is exercised end-to-end, just without any provider,
// scheduler, or stub timer behaviour to introduce flakes.
package fakeserver

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/mpetters/nowplaying/internal/ipc"
	"github.com/mpetters/nowplaying/internal/proto"
)

// Server is a test-controlled fake daemon.
type Server struct {
	t      *testing.T
	server *ipc.Server
	sock   string

	mu    sync.RWMutex
	state proto.PlayerState

	subs sync.Map // *ipc.Client -> struct{}

	cancel context.CancelFunc
	doneCh chan struct{}
}

var sockCounter atomic.Uint64

// Start spins up a fakeserver on a temp socket and registers cleanups
// so it shuts down when the test finishes. The returned Server is ready
// to accept connections.
func Start(t *testing.T, initial proto.PlayerState) *Server {
	t.Helper()

	sock := tempSocket(t)
	srv := ipc.NewServer(ipc.Config{SocketPath: sock})

	fs := &Server{
		t:      t,
		server: srv,
		sock:   sock,
		state:  initial,
		doneCh: make(chan struct{}),
	}

	srv.Handle(proto.MethodStateGet, fs.handleStateGet)
	// Transport methods are no-ops — they exist so the TUI's "press
	// space" key path doesn't surface an "unknown method" error.
	for _, m := range []string{
		proto.MethodTransportToggle,
		proto.MethodTransportPlay,
		proto.MethodTransportPause,
		proto.MethodTransportNext,
		proto.MethodTransportPrev,
	} {
		srv.Handle(m, func(context.Context, json.RawMessage) (any, error) {
			return map[string]any{"ok": true}, nil
		})
	}
	srv.OnSubscribe(func(c *ipc.Client) {
		fs.subs.Store(c, struct{}{})
	})

	ctx, cancel := context.WithCancel(context.Background())
	fs.cancel = cancel
	go func() {
		defer close(fs.doneCh)
		if err := srv.Serve(ctx); err != nil {
			t.Logf("fakeserver: serve returned: %v", err)
		}
	}()

	t.Cleanup(fs.Stop)

	if err := waitForSocket(sock, 2*time.Second); err != nil {
		t.Fatalf("fakeserver: socket never came up: %v", err)
	}
	return fs
}

// Socket returns the unix socket path the server is listening on.
func (s *Server) Socket() string { return s.sock }

// SetState replaces the published state. Callers may follow up with
// PushStateChanged to notify subscribers.
func (s *Server) SetState(p proto.PlayerState) {
	s.mu.Lock()
	s.state = p
	s.mu.Unlock()
}

// State returns the currently published state.
func (s *Server) State() proto.PlayerState {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.state
}

// PushStateChanged broadcasts a state.changed notification carrying p.
// Tests use this to drive the TUI through state transitions.
func (s *Server) PushStateChanged(p proto.PlayerState) {
	s.SetState(p)
	s.server.Broadcast(proto.NotifyStateChanged, p)
}

// PushProgressTick broadcasts a progress.tick notification.
func (s *Server) PushProgressTick(positionMS, durationMS int64) {
	s.server.Broadcast(proto.NotifyProgressTick, proto.ProgressTick{
		PositionMS: positionMS,
		DurationMS: durationMS,
		TS:         time.Now().UnixMilli(),
	})
}

// Stop shuts the server down. Idempotent.
func (s *Server) Stop() {
	if s.cancel == nil {
		return
	}
	s.cancel()
	s.cancel = nil
	_ = s.server.Stop()
	select {
	case <-s.doneCh:
	case <-time.After(2 * time.Second):
		s.t.Logf("fakeserver: shutdown timeout")
	}
}

func (s *Server) handleStateGet(_ context.Context, _ json.RawMessage) (any, error) {
	return s.State(), nil
}

func tempSocket(t *testing.T) string {
	t.Helper()
	n := sockCounter.Add(1)
	// Keep the path short — Linux caps unix socket paths at 108 bytes,
	// macOS at 104. t.TempDir() under /var/folders blows past that on
	// CI for nested test names.
	sock := filepath.Join("/tmp", fmt.Sprintf("np-fake-%d-%d.sock", os.Getpid(), n))
	t.Cleanup(func() { _ = os.Remove(sock) })
	return sock
}

func waitForSocket(path string, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if _, err := os.Stat(path); err == nil {
			return nil
		}
		time.Sleep(10 * time.Millisecond)
	}
	return fmt.Errorf("socket %q not ready within %s", path, timeout)
}
