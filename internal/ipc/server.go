// Package ipc serves the JSON-RPC protocol over a Unix domain socket.
// It owns the network plumbing; method dispatch and notification
// fan-out are wired in by the daemon (cmd/nowplayingd) to keep this
// package independent of state and provider concerns.
package ipc

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"os"
	"path/filepath"
	"sync"
	"sync/atomic"

	"github.com/mpetters/nowplaying/internal/proto"
)

// Handler implements one RPC method. Returns either a result value (any
// JSON-serializable type) or an error. Returning an *proto.Error lets
// handlers control the wire-level code.
type Handler func(ctx context.Context, params json.RawMessage) (any, error)

// Server hosts the Unix-socket listener and routes incoming requests.
type Server struct {
	socketPath string
	handlers   map[string]Handler
	logger     *slog.Logger

	listener net.Listener

	mu      sync.RWMutex
	clients map[uint64]*Client
	nextID  uint64

	// onSubscribe is called when a client invokes state.subscribe so
	// the daemon can wire it up to the state machine.
	onSubscribe func(c *Client)
}

// Config carries server configuration.
type Config struct {
	SocketPath string
	Logger     *slog.Logger
}

func NewServer(cfg Config) *Server {
	if cfg.Logger == nil {
		cfg.Logger = slog.Default()
	}
	return &Server{
		socketPath: cfg.SocketPath,
		handlers:   make(map[string]Handler),
		clients:    make(map[uint64]*Client),
		logger:     cfg.Logger,
	}
}

// Handle registers a handler for the given method name. Calling Handle
// after Serve returns is allowed but not goroutine-safe with in-flight
// requests; register everything before calling Serve.
func (s *Server) Handle(method string, h Handler) {
	s.handlers[method] = h
}

// OnSubscribe registers a callback invoked when a client issues
// state.subscribe. The callback should attach the client to whatever
// notification stream the daemon owns.
func (s *Server) OnSubscribe(fn func(c *Client)) {
	s.onSubscribe = fn
}

// Serve listens on the configured socket path and accepts connections
// until ctx is canceled or Stop is called.
func (s *Server) Serve(ctx context.Context) error {
	if err := os.MkdirAll(filepath.Dir(s.socketPath), 0o700); err != nil {
		return fmt.Errorf("ensure socket dir: %w", err)
	}
	// Best effort: remove a stale socket from a prior daemon crash.
	_ = os.Remove(s.socketPath)

	ln, err := net.Listen("unix", s.socketPath)
	if err != nil {
		return fmt.Errorf("listen %s: %w", s.socketPath, err)
	}
	if err := os.Chmod(s.socketPath, 0o600); err != nil {
		_ = ln.Close()
		return fmt.Errorf("chmod socket: %w", err)
	}
	s.listener = ln

	go func() {
		<-ctx.Done()
		_ = ln.Close()
	}()

	for {
		conn, err := ln.Accept()
		if err != nil {
			if errors.Is(err, net.ErrClosed) || ctx.Err() != nil {
				s.closeAllClients()
				return nil
			}
			s.logger.Warn("accept error", "err", err)
			continue
		}
		s.startClient(ctx, conn)
	}
}

// Stop closes the listener and disconnects all clients.
func (s *Server) Stop() error {
	if s.listener != nil {
		_ = s.listener.Close()
	}
	s.closeAllClients()
	return os.Remove(s.socketPath)
}

// Broadcast sends a notification to every subscribed client. Used by
// the daemon to fan out state events.
func (s *Server) Broadcast(method string, body any) {
	msg, err := proto.NewNotification(method, body)
	if err != nil {
		s.logger.Error("encode broadcast", "method", method, "err", err)
		return
	}
	s.mu.RLock()
	subs := make([]*Client, 0, len(s.clients))
	for _, c := range s.clients {
		if c.Subscribed() {
			subs = append(subs, c)
		}
	}
	s.mu.RUnlock()
	for _, c := range subs {
		if err := c.Send(msg); err != nil {
			s.logger.Debug("client send dropped", "client", c.id, "err", err)
		}
	}
}

func (s *Server) startClient(ctx context.Context, conn net.Conn) {
	id := atomic.AddUint64(&s.nextID, 1)
	c := &Client{
		id:     id,
		conn:   conn,
		reader: proto.NewReader(conn),
		writer: proto.NewWriter(conn),
		logger: s.logger.With("client", id),
	}
	s.mu.Lock()
	s.clients[id] = c
	s.mu.Unlock()
	go s.serveClient(ctx, c)
}

func (s *Server) serveClient(ctx context.Context, c *Client) {
	defer func() {
		_ = c.conn.Close()
		s.mu.Lock()
		delete(s.clients, c.id)
		s.mu.Unlock()
		c.logger.Debug("client disconnected")
	}()

	for {
		msg, err := c.reader.Read()
		if err != nil {
			if !errors.Is(err, io.EOF) && !errors.Is(err, net.ErrClosed) {
				c.logger.Debug("read error", "err", err)
			}
			return
		}
		if err := msg.Validate(); err != nil {
			s.replyError(c, msg.ID, proto.CodeInvalidRequest, err.Error())
			continue
		}
		if msg.IsRequest() {
			s.dispatch(ctx, c, msg)
		}
		// We don't expect the client to send notifications or responses.
	}
}

func (s *Server) dispatch(ctx context.Context, c *Client, req *proto.Message) {
	if req.Method == proto.MethodStateSubscribe {
		c.setSubscribed(true)
		if s.onSubscribe != nil {
			s.onSubscribe(c)
		}
		s.replySuccess(c, req.ID, map[string]any{"ok": true})
		return
	}

	h, ok := s.handlers[req.Method]
	if !ok {
		s.replyError(c, req.ID, proto.CodeMethodNotFound, "method not found: "+req.Method)
		return
	}
	result, err := h(ctx, req.Params)
	if err != nil {
		var perr *proto.Error
		if errors.As(err, &perr) {
			s.replyErrorRaw(c, req.ID, perr)
			return
		}
		s.replyError(c, req.ID, proto.CodeInternalError, err.Error())
		return
	}
	s.replySuccess(c, req.ID, result)
}

func (s *Server) replySuccess(c *Client, id *json.RawMessage, result any) {
	if id == nil {
		return
	}
	resp, err := proto.NewResponse(*id, result)
	if err != nil {
		s.logger.Error("encode response", "err", err)
		return
	}
	_ = c.Send(resp)
}

func (s *Server) replyError(c *Client, id *json.RawMessage, code int, msg string) {
	if id == nil {
		return
	}
	resp, err := proto.NewErrorResponse(*id, code, msg, nil)
	if err != nil {
		s.logger.Error("encode error response", "err", err)
		return
	}
	_ = c.Send(resp)
}

func (s *Server) replyErrorRaw(c *Client, id *json.RawMessage, perr *proto.Error) {
	if id == nil {
		return
	}
	m := &proto.Message{JSONRPC: "2.0", ID: id, Error: perr}
	_ = c.Send(m)
}

func (s *Server) closeAllClients() {
	s.mu.Lock()
	clients := make([]*Client, 0, len(s.clients))
	for _, c := range s.clients {
		clients = append(clients, c)
	}
	s.clients = make(map[uint64]*Client)
	s.mu.Unlock()
	for _, c := range clients {
		_ = c.conn.Close()
	}
}

// Client represents one connected client.
type Client struct {
	id     uint64
	conn   net.Conn
	reader *proto.Reader
	writer *proto.Writer
	logger *slog.Logger

	subMu      sync.RWMutex
	subscribed bool
}

func (c *Client) Send(m *proto.Message) error {
	return c.writer.Write(m)
}

func (c *Client) Subscribed() bool {
	c.subMu.RLock()
	defer c.subMu.RUnlock()
	return c.subscribed
}

func (c *Client) setSubscribed(v bool) {
	c.subMu.Lock()
	defer c.subMu.Unlock()
	c.subscribed = v
}
