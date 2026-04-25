package daemon

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"

	"github.com/mpetters/nowplaying/internal/ipc"
	"github.com/mpetters/nowplaying/internal/proto"
	"github.com/mpetters/nowplaying/internal/providers/stub"
)

var sockCounter atomic.Uint64

func TestDaemon_EndToEnd(t *testing.T) {
	sock := tempSock(t)
	d := New(Config{SocketPath: sock})
	d.Register(stub.New())

	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	done := make(chan error, 1)
	go func() { done <- d.Run(ctx) }()
	t.Cleanup(func() {
		cancel()
		<-done
	})

	c := dialClient(t, ctx, sock)
	t.Cleanup(func() { _ = c.Close() })

	// state.get returns whatever the stub has published so far.
	raw, err := c.Call(ctx, proto.MethodStateGet, nil)
	if err != nil {
		t.Fatalf("state.get: %v", err)
	}
	var ps proto.PlayerState
	if err := json.Unmarshal(raw, &ps); err != nil {
		t.Fatalf("decode state: %v", err)
	}
	// Stub may not have ticked yet; wait for the first observation.
	if ps.Provider == "" {
		raw = waitForState(t, ctx, c)
		if err := json.Unmarshal(raw, &ps); err != nil {
			t.Fatalf("decode state: %v", err)
		}
	}
	if ps.Provider != "stub" {
		t.Errorf("provider = %q", ps.Provider)
	}

	// Subscribe and verify we get notifications. The stub publishes a
	// progress tick on every poll while it's playing, so that's the
	// most reliable signal that the broadcast pipeline works.
	if _, err := c.Call(ctx, proto.MethodStateSubscribe, nil); err != nil {
		t.Fatalf("subscribe: %v", err)
	}
	if !waitForNotification(t, c, proto.NotifyProgressTick, 2*time.Second) {
		t.Fatal("no progress.tick notification received")
	}

	// Pause via transport; verify status flips.
	if _, err := c.Call(ctx, proto.MethodTransportPause, nil); err != nil {
		t.Fatalf("pause: %v", err)
	}
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		raw, err := c.Call(ctx, proto.MethodStateGet, nil)
		if err != nil {
			t.Fatalf("state.get after pause: %v", err)
		}
		var s proto.PlayerState
		if err := json.Unmarshal(raw, &s); err != nil {
			t.Fatalf("decode: %v", err)
		}
		if s.Status == proto.StatusPaused {
			return
		}
		time.Sleep(50 * time.Millisecond)
	}
	t.Fatal("pause did not propagate to canonical state")
}

func TestDaemon_ProviderList(t *testing.T) {
	sock := tempSock(t)
	d := New(Config{SocketPath: sock})
	d.Register(stub.New())

	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	done := make(chan error, 1)
	go func() { done <- d.Run(ctx) }()
	t.Cleanup(func() { cancel(); <-done })

	c := dialClient(t, ctx, sock)
	t.Cleanup(func() { _ = c.Close() })

	raw, err := c.Call(ctx, proto.MethodProviderList, nil)
	if err != nil {
		t.Fatalf("provider.list: %v", err)
	}
	var infos []proto.ProviderInfo
	if err := json.Unmarshal(raw, &infos); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(infos) != 1 || !infos[0].Active || infos[0].Name != "stub" {
		t.Errorf("infos = %+v", infos)
	}
}

func TestDaemon_UnknownProviderRejected(t *testing.T) {
	sock := tempSock(t)
	d := New(Config{SocketPath: sock})
	d.Register(stub.New())

	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	done := make(chan error, 1)
	go func() { done <- d.Run(ctx) }()
	t.Cleanup(func() { cancel(); <-done })

	c := dialClient(t, ctx, sock)
	t.Cleanup(func() { _ = c.Close() })

	_, err := c.Call(ctx, proto.MethodProviderSet, proto.ProviderSetParams{Provider: "ghost"})
	if err == nil {
		t.Fatal("expected error")
	}
}

func tempSock(t *testing.T) string {
	t.Helper()
	n := sockCounter.Add(1)
	sock := filepath.Join("/tmp", fmt.Sprintf("npd-%d-%d.sock", os.Getpid(), n))
	t.Cleanup(func() { _ = os.Remove(sock) })
	return sock
}

func dialClient(t *testing.T, ctx context.Context, sock string) *ipc.ConnClient {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for {
		c, err := ipc.DialClient(ctx, sock)
		if err == nil {
			return c
		}
		if time.Now().After(deadline) {
			t.Fatalf("dial: %v", err)
		}
		time.Sleep(20 * time.Millisecond)
	}
}

func waitForState(t *testing.T, ctx context.Context, c *ipc.ConnClient) json.RawMessage {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		raw, err := c.Call(ctx, proto.MethodStateGet, nil)
		if err != nil {
			t.Fatalf("state.get: %v", err)
		}
		var ps proto.PlayerState
		_ = json.Unmarshal(raw, &ps)
		if ps.Provider != "" {
			return raw
		}
		time.Sleep(50 * time.Millisecond)
	}
	t.Fatal("state never populated")
	return nil
}

func waitForNotification(t *testing.T, c *ipc.ConnClient, method string, timeout time.Duration) bool {
	t.Helper()
	deadline := time.After(timeout)
	for {
		select {
		case n, ok := <-c.Notifications():
			if !ok {
				return false
			}
			if n.Method == method {
				return true
			}
		case <-deadline:
			return false
		}
	}
}
