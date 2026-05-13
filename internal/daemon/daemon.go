// Package daemon wires the IPC server, state machine, and providers
// into a single runnable unit. It owns no transport details — the
// cmd/nowplayingd binary translates flags into a Config and calls Run.
package daemon

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"sync"

	"github.com/mpetters/nowplaying/internal/ipc"
	"github.com/mpetters/nowplaying/internal/proto"
	"github.com/mpetters/nowplaying/internal/providers"
	"github.com/mpetters/nowplaying/internal/state"
)

// Config carries daemon settings.
type Config struct {
	SocketPath string
	Logger     *slog.Logger
}

// Daemon is the running daemon.
type Daemon struct {
	cfg     Config
	machine *state.Machine
	server  *ipc.Server
	logger  *slog.Logger

	mu        sync.RWMutex
	providers []providers.Provider
	active    providers.Provider
}

func New(cfg Config) *Daemon {
	if cfg.Logger == nil {
		cfg.Logger = slog.Default()
	}
	return &Daemon{
		cfg:     cfg,
		machine: state.NewMachine(),
		logger:  cfg.Logger,
	}
}

// Register adds a provider. The first provider registered becomes the
// active one until ProviderSet is called.
func (d *Daemon) Register(p providers.Provider) {
	d.mu.Lock()
	defer d.mu.Unlock()
	d.providers = append(d.providers, p)
	if d.active == nil {
		d.active = p
	}
}

// Machine exposes the state machine for tests.
func (d *Daemon) Machine() *state.Machine { return d.machine }

// Run starts the IPC server and provider goroutines. It blocks until ctx
// is canceled.
func (d *Daemon) Run(ctx context.Context) error {
	d.server = ipc.NewServer(ipc.Config{
		SocketPath: d.cfg.SocketPath,
		Logger:     d.logger,
	})
	d.registerHandlers()

	// Subscribe to the state machine and forward notifications to all
	// connected clients.
	subID, ch := d.machine.Subscribe(128)
	defer d.machine.Unsubscribe(subID)
	go d.forwardNotifications(ctx, ch)

	// Start provider goroutines.
	d.mu.RLock()
	provs := append([]providers.Provider(nil), d.providers...)
	d.mu.RUnlock()
	var wg sync.WaitGroup
	for _, p := range provs {
		wg.Add(1)
		go func(p providers.Provider) {
			defer wg.Done()
			if err := p.Run(ctx, d.machine); err != nil && !errors.Is(err, context.Canceled) {
				d.logger.Error("provider stopped", "provider", p.Name(), "err", err)
			}
		}(p)
	}

	defer wg.Wait()
	return d.server.Serve(ctx)
}

func (d *Daemon) forwardNotifications(ctx context.Context, ch <-chan state.Notification) {
	for {
		select {
		case <-ctx.Done():
			return
		case n, ok := <-ch:
			if !ok {
				return
			}
			d.server.Broadcast(n.Method, n.Body)
		}
	}
}

func (d *Daemon) registerHandlers() {
	d.server.Handle(proto.MethodStateGet, func(ctx context.Context, _ json.RawMessage) (any, error) {
		return d.machine.Get(), nil
	})

	d.server.Handle(proto.MethodTransportPlay, d.transport(func(ctx context.Context, p providers.Provider) error {
		return p.Play(ctx)
	}))
	d.server.Handle(proto.MethodTransportPause, d.transport(func(ctx context.Context, p providers.Provider) error {
		return p.Pause(ctx)
	}))
	d.server.Handle(proto.MethodTransportToggle, d.transport(func(ctx context.Context, p providers.Provider) error {
		s := d.machine.Get()
		if s.Status == proto.StatusPlaying {
			return p.Pause(ctx)
		}
		return p.Play(ctx)
	}))
	d.server.Handle(proto.MethodTransportNext, d.transport(func(ctx context.Context, p providers.Provider) error {
		return p.Next(ctx)
	}))
	d.server.Handle(proto.MethodTransportPrev, d.transport(func(ctx context.Context, p providers.Provider) error {
		return p.Prev(ctx)
	}))
	d.server.Handle(proto.MethodTransportSeek, func(ctx context.Context, params json.RawMessage) (any, error) {
		var sp proto.SeekParams
		if err := json.Unmarshal(params, &sp); err != nil {
			return nil, &proto.Error{Code: proto.CodeInvalidParams, Message: err.Error()}
		}
		p := d.activeProvider()
		if p == nil {
			return nil, &proto.Error{Code: proto.CodeNotConnected, Message: "no active provider"}
		}
		d.machine.MarkCommandIssued()
		if err := p.Seek(ctx, sp.MS); err != nil {
			return nil, err
		}
		return map[string]bool{"ok": true}, nil
	})
	d.server.Handle(proto.MethodTransportVolume, func(ctx context.Context, params json.RawMessage) (any, error) {
		var vp proto.VolumeParams
		if err := json.Unmarshal(params, &vp); err != nil {
			return nil, &proto.Error{Code: proto.CodeInvalidParams, Message: err.Error()}
		}
		p := d.activeProvider()
		if p == nil {
			return nil, &proto.Error{Code: proto.CodeNotConnected, Message: "no active provider"}
		}
		d.machine.MarkCommandIssued()
		if err := p.SetVolume(ctx, vp.Level); err != nil {
			return nil, err
		}
		return map[string]bool{"ok": true}, nil
	})

	d.server.Handle(proto.MethodSearchPlay, func(ctx context.Context, params json.RawMessage) (any, error) {
		var sp proto.SearchPlayParams
		if err := json.Unmarshal(params, &sp); err != nil {
			return nil, &proto.Error{Code: proto.CodeInvalidParams, Message: err.Error()}
		}
		p := d.activeProvider()
		if p == nil {
			return nil, &proto.Error{Code: proto.CodeNotConnected, Message: "no active provider"}
		}
		up, ok := p.(providers.URIPlayer)
		if !ok {
			return nil, &proto.Error{Code: proto.CodeProviderError, Message: fmt.Sprintf("%s does not support URI playback", p.Name())}
		}
		d.machine.MarkCommandIssued()
		if err := up.PlayURI(ctx, sp.URI); err != nil {
			return nil, err
		}
		return map[string]bool{"ok": true}, nil
	})

	d.server.Handle(proto.MethodLikeToggle, func(ctx context.Context, _ json.RawMessage) (any, error) {
		p := d.activeProvider()
		if p == nil {
			return nil, &proto.Error{Code: proto.CodeNotConnected, Message: "no active provider"}
		}
		lk, ok := p.(providers.Liker)
		if !ok {
			return nil, &proto.Error{Code: proto.CodeProviderError, Message: fmt.Sprintf("%s does not support like/unlike", p.Name())}
		}
		liked, err := lk.LikeToggle(ctx)
		if err != nil {
			return nil, err
		}
		return proto.LikeToggleResult{Liked: liked}, nil
	})

	d.server.Handle(proto.MethodProviderList, func(ctx context.Context, _ json.RawMessage) (any, error) {
		d.mu.RLock()
		defer d.mu.RUnlock()
		out := make([]proto.ProviderInfo, 0, len(d.providers))
		for _, p := range d.providers {
			out = append(out, proto.ProviderInfo{
				Name:      p.Name(),
				Active:    p == d.active,
				Available: p.Available(ctx),
			})
		}
		return out, nil
	})
	d.server.Handle(proto.MethodProviderSet, func(ctx context.Context, params json.RawMessage) (any, error) {
		var ps proto.ProviderSetParams
		if err := json.Unmarshal(params, &ps); err != nil {
			return nil, &proto.Error{Code: proto.CodeInvalidParams, Message: err.Error()}
		}
		d.mu.Lock()
		defer d.mu.Unlock()
		for _, p := range d.providers {
			if p.Name() == ps.Provider {
				d.active = p
				return map[string]bool{"ok": true}, nil
			}
		}
		return nil, &proto.Error{Code: proto.CodeInvalidParams, Message: fmt.Sprintf("unknown provider: %s", ps.Provider)}
	})
}

func (d *Daemon) transport(fn func(ctx context.Context, p providers.Provider) error) ipc.Handler {
	return func(ctx context.Context, _ json.RawMessage) (any, error) {
		p := d.activeProvider()
		if p == nil {
			return nil, &proto.Error{Code: proto.CodeNotConnected, Message: "no active provider"}
		}
		d.machine.MarkCommandIssued()
		if err := fn(ctx, p); err != nil {
			return nil, err
		}
		return map[string]bool{"ok": true}, nil
	}
}

// BroadcastSpectrum sends audio spectrum data directly to all subscribed
// clients, bypassing the state machine (spectrum is ephemeral).
func (d *Daemon) BroadcastSpectrum(bands []float64, samples []float64) {
	if d.server == nil {
		return
	}
	d.server.Broadcast(proto.NotifyAudioSpectrum, proto.AudioSpectrum{
		Bands:   bands,
		Samples: samples,
	})
}

func (d *Daemon) activeProvider() providers.Provider {
	d.mu.RLock()
	defer d.mu.RUnlock()
	return d.active
}
