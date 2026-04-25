package ipc

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"sync"
	"sync/atomic"
	"time"

	"github.com/mpetters/nowplaying/internal/proto"
)

// DialClient connects to a daemon listening on socketPath.
func DialClient(ctx context.Context, socketPath string) (*ConnClient, error) {
	d := net.Dialer{}
	conn, err := d.DialContext(ctx, "unix", socketPath)
	if err != nil {
		return nil, fmt.Errorf("dial %s: %w", socketPath, err)
	}
	c := &ConnClient{
		conn:    conn,
		reader:  proto.NewReader(conn),
		writer:  proto.NewWriter(conn),
		pending: make(map[string]chan *proto.Message),
		notify:  make(chan *proto.Message, 64),
	}
	go c.readLoop()
	return c, nil
}

// ConnClient is a thin RPC client over a single socket connection.
type ConnClient struct {
	conn   net.Conn
	reader *proto.Reader
	writer *proto.Writer

	mu      sync.Mutex
	pending map[string]chan *proto.Message
	closed  atomic.Bool

	notify chan *proto.Message
	nextID atomic.Uint64
}

// Notifications returns the channel of server-pushed notifications.
func (c *ConnClient) Notifications() <-chan *proto.Message {
	return c.notify
}

// Call performs a request/response exchange. Caller decodes result.
func (c *ConnClient) Call(ctx context.Context, method string, params any) (json.RawMessage, error) {
	id := fmt.Sprintf("c-%d", c.nextID.Add(1))
	req, err := proto.NewRequest(id, method, params)
	if err != nil {
		return nil, err
	}
	ch := make(chan *proto.Message, 1)
	c.mu.Lock()
	c.pending[id] = ch
	c.mu.Unlock()
	defer func() {
		c.mu.Lock()
		delete(c.pending, id)
		c.mu.Unlock()
	}()

	if err := c.writer.Write(req); err != nil {
		return nil, fmt.Errorf("write: %w", err)
	}
	select {
	case <-ctx.Done():
		return nil, ctx.Err()
	case resp, ok := <-ch:
		if !ok {
			return nil, errors.New("connection closed")
		}
		if resp.Error != nil {
			return nil, resp.Error
		}
		return resp.Result, nil
	}
}

// Close shuts the connection down.
func (c *ConnClient) Close() error {
	if c.closed.Swap(true) {
		return nil
	}
	err := c.conn.Close()
	c.mu.Lock()
	for _, ch := range c.pending {
		close(ch)
	}
	c.pending = make(map[string]chan *proto.Message)
	c.mu.Unlock()
	close(c.notify)
	return err
}

func (c *ConnClient) readLoop() {
	for {
		msg, err := c.reader.Read()
		if err != nil {
			if !errors.Is(err, io.EOF) && !c.closed.Load() {
				// Best-effort: notify pending callers.
			}
			c.Close()
			return
		}
		if msg.IsResponse() {
			c.routeResponse(msg)
			continue
		}
		if msg.IsNotification() {
			select {
			case c.notify <- msg:
			default:
				// Drop if subscriber isn't keeping up.
			}
		}
	}
}

func (c *ConnClient) routeResponse(msg *proto.Message) {
	if msg.ID == nil {
		return
	}
	var id string
	// id might be a string or number; we always send strings.
	if err := json.Unmarshal(*msg.ID, &id); err != nil {
		return
	}
	c.mu.Lock()
	ch, ok := c.pending[id]
	c.mu.Unlock()
	if !ok {
		return
	}
	select {
	case ch <- msg:
	case <-time.After(5 * time.Second):
		// Receiver gone; drop.
	}
}
