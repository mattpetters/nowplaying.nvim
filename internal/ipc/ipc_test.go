package ipc

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/mpetters/nowplaying/internal/proto"
)

var sockCounter atomic.Uint64

func TestServer_RoundTrip(t *testing.T) {
	srv, sock := newTestServer(t)
	srv.Handle(proto.MethodStateGet, func(ctx context.Context, _ json.RawMessage) (any, error) {
		return proto.PlayerState{Provider: "stub", Status: proto.StatusPaused, Volume: 50}, nil
	})

	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	go func() { _ = srv.Serve(ctx) }()
	t.Cleanup(func() { _ = srv.Stop() })

	c := dialClient(t, ctx, sock)
	t.Cleanup(func() { _ = c.Close() })

	raw, err := c.Call(ctx, proto.MethodStateGet, nil)
	if err != nil {
		t.Fatalf("Call: %v", err)
	}
	var got proto.PlayerState
	if err := json.Unmarshal(raw, &got); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if got.Provider != "stub" || got.Volume != 50 {
		t.Errorf("got %+v", got)
	}
}

func TestServer_MethodNotFound(t *testing.T) {
	srv, sock := newTestServer(t)
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	go func() { _ = srv.Serve(ctx) }()
	t.Cleanup(func() { _ = srv.Stop() })

	c := dialClient(t, ctx, sock)
	t.Cleanup(func() { _ = c.Close() })

	_, err := c.Call(ctx, "no.such.method", nil)
	var perr *proto.Error
	if !errors.As(err, &perr) {
		t.Fatalf("want proto.Error, got %v", err)
	}
	if perr.Code != proto.CodeMethodNotFound {
		t.Errorf("code = %d", perr.Code)
	}
}

func TestServer_HandlerErrorBubblesAsInternal(t *testing.T) {
	srv, sock := newTestServer(t)
	srv.Handle("boom", func(_ context.Context, _ json.RawMessage) (any, error) {
		return nil, errors.New("kaboom")
	})
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	go func() { _ = srv.Serve(ctx) }()
	t.Cleanup(func() { _ = srv.Stop() })

	c := dialClient(t, ctx, sock)
	t.Cleanup(func() { _ = c.Close() })

	_, err := c.Call(ctx, "boom", nil)
	var perr *proto.Error
	if !errors.As(err, &perr) || perr.Code != proto.CodeInternalError {
		t.Fatalf("want internal error, got %v", err)
	}
}

func TestServer_TypedProtoErrorPreservesCode(t *testing.T) {
	srv, sock := newTestServer(t)
	srv.Handle("authrequired", func(_ context.Context, _ json.RawMessage) (any, error) {
		return nil, &proto.Error{Code: proto.CodeAuthRequired, Message: "log in first"}
	})
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	go func() { _ = srv.Serve(ctx) }()
	t.Cleanup(func() { _ = srv.Stop() })

	c := dialClient(t, ctx, sock)
	t.Cleanup(func() { _ = c.Close() })

	_, err := c.Call(ctx, "authrequired", nil)
	var perr *proto.Error
	if !errors.As(err, &perr) || perr.Code != proto.CodeAuthRequired {
		t.Fatalf("want auth required, got %v", err)
	}
}

func TestServer_BroadcastReachesSubscribers(t *testing.T) {
	srv, sock := newTestServer(t)
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	go func() { _ = srv.Serve(ctx) }()
	t.Cleanup(func() { _ = srv.Stop() })

	subscribed := make(chan struct{}, 2)
	srv.OnSubscribe(func(_ *Client) { subscribed <- struct{}{} })

	c1 := dialClient(t, ctx, sock)
	c2 := dialClient(t, ctx, sock)
	t.Cleanup(func() { _ = c1.Close(); _ = c2.Close() })

	for _, c := range []*ConnClient{c1, c2} {
		if _, err := c.Call(ctx, proto.MethodStateSubscribe, nil); err != nil {
			t.Fatalf("subscribe: %v", err)
		}
	}
	// Wait for the server to record both subscribers.
	for range 2 {
		select {
		case <-subscribed:
		case <-time.After(2 * time.Second):
			t.Fatal("OnSubscribe not invoked")
		}
	}

	// Broadcast; both clients should receive it.
	srv.Broadcast(proto.NotifyTrackChanged, proto.TrackChanged{
		Current: &proto.Track{Title: "Hey"},
	})

	var wg sync.WaitGroup
	wg.Add(2)
	for _, c := range []*ConnClient{c1, c2} {
		go func(c *ConnClient) {
			defer wg.Done()
			select {
			case n := <-c.Notifications():
				if n.Method != proto.NotifyTrackChanged {
					t.Errorf("got method %q", n.Method)
				}
			case <-time.After(2 * time.Second):
				t.Error("client missed broadcast")
			}
		}(c)
	}
	wg.Wait()
}

func TestServer_RejectsInvalidFrame(t *testing.T) {
	srv, sock := newTestServer(t)
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	go func() { _ = srv.Serve(ctx) }()
	t.Cleanup(func() { _ = srv.Stop() })

	c := dialClient(t, ctx, sock)
	t.Cleanup(func() { _ = c.Close() })

	// Hand-craft a frame with both result and error to fail Validate.
	bad := &proto.Message{
		JSONRPC: "2.0",
		ID:      rawID(99),
		Result:  json.RawMessage(`{}`),
		Error:   &proto.Error{Code: 1, Message: "x"},
	}
	if err := c.writer.Write(bad); err != nil {
		t.Fatalf("write: %v", err)
	}
	select {
	case msg := <-c.Notifications():
		t.Fatalf("unexpected notification: %+v", msg)
	case <-time.After(200 * time.Millisecond):
		// No reply expected (id present, but server detected invalid request and replied to id).
	}
	// The id we sent (99) is not a pending call, so the response gets
	// dropped by routeResponse. Sanity-check: the connection should
	// still be usable.
	srv.Handle("ping", func(context.Context, json.RawMessage) (any, error) { return "pong", nil })
	if _, err := c.Call(ctx, "ping", nil); err != nil {
		t.Fatalf("connection dead after bad frame: %v", err)
	}
}

func newTestServer(t *testing.T) (*Server, string) {
	t.Helper()
	// Unix sockets on macOS cap the path at ~104 bytes, so t.TempDir()
	// (which lives deep under $TMPDIR) is too long. Use a short path
	// under /tmp and clean it up ourselves.
	n := sockCounter.Add(1)
	sock := filepath.Join("/tmp", fmt.Sprintf("npd-test-%d-%d.sock", os.Getpid(), n))
	t.Cleanup(func() { _ = os.Remove(sock) })
	return NewServer(Config{SocketPath: sock}), sock
}

func dialClient(t *testing.T, ctx context.Context, sock string) *ConnClient {
	t.Helper()
	// Wait for the server to start listening.
	deadline := time.Now().Add(2 * time.Second)
	for {
		c, err := DialClient(ctx, sock)
		if err == nil {
			return c
		}
		if time.Now().After(deadline) {
			t.Fatalf("dial: %v", err)
		}
		time.Sleep(20 * time.Millisecond)
	}
}

func rawID(n int) *json.RawMessage {
	b, _ := json.Marshal(n)
	r := json.RawMessage(b)
	return &r
}
