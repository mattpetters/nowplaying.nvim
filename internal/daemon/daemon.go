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
	"time"

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

	mu            sync.RWMutex
	providers     []providers.Provider
	active        providers.Provider
	activeCancel  context.CancelFunc
	activeRunning bool
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

// Register adds a provider. Providers are registered in priority order;
// the first available provider becomes active.
func (d *Daemon) Register(p providers.Provider) {
	d.mu.Lock()
	defer d.mu.Unlock()
	d.providers = append(d.providers, p)
	if d.active == nil && p.Available(context.Background()) {
		d.active = p
	}
}

// ActiveProviderName returns the name of the currently active provider,
// or "none" if no provider is active.
func (d *Daemon) ActiveProviderName() string {
	d.mu.RLock()
	defer d.mu.RUnlock()
	if d.active == nil {
		return "none"
	}
	return d.active.Name()
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

	// If no provider was selected during registration (none available),
	// fall back to the last registered provider (stub).
	d.mu.Lock()
	if d.active == nil && len(d.providers) > 0 {
		d.active = d.providers[len(d.providers)-1]
	}
	d.mu.Unlock()

	// Start only the active provider's goroutine.
	d.startActiveProvider(ctx)

	// Watch for provider availability changes (e.g. Spotify launched
	// after daemon started with stub).
	go d.watchProviders(ctx)

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
		trackID := ""
		if s := d.machine.Get(); s.Track != nil {
			trackID = s.Track.ID
		}
		liked, err := lk.LikeToggle(ctx, trackID)
		if err != nil {
			return nil, err
		}
		return proto.LikeToggleResult{Liked: liked}, nil
	})

	d.server.Handle(proto.MethodSearchQuery, func(ctx context.Context, params json.RawMessage) (any, error) {
		var sq proto.SearchQueryParams
		if err := json.Unmarshal(params, &sq); err != nil {
			return nil, &proto.Error{Code: proto.CodeInvalidParams, Message: err.Error()}
		}
		p := d.activeProvider()
		if p == nil {
			return nil, &proto.Error{Code: proto.CodeNotConnected, Message: "no active provider"}
		}
		sr, ok := p.(providers.Searcher)
		if !ok {
			return nil, &proto.Error{Code: proto.CodeProviderError, Message: fmt.Sprintf("%s does not support search", p.Name())}
		}
		tracks, err := sr.Search(ctx, sq.Q, sq.Limit)
		if err != nil {
			return nil, &proto.Error{Code: proto.CodeProviderError, Message: err.Error()}
		}
		result := proto.SearchResult{
			Tracks: make([]proto.Track, len(tracks)),
		}
		for i, t := range tracks {
			result.Tracks[i] = proto.Track{
				ID:         t.ID,
				URI:        t.URI,
				Title:      t.Title,
				Artist:     t.Artist,
				Album:      t.Album,
				DurationMS: t.DurationMS,
				ArtworkURL: t.ArtworkURL,
			}
		}
		return result, nil
	})

	d.server.Handle(proto.MethodAuthStart, func(ctx context.Context, _ json.RawMessage) (any, error) {
		p := d.activeProvider()
		if p == nil {
			return nil, &proto.Error{Code: proto.CodeNotConnected, Message: "no active provider"}
		}
		au, ok := p.(providers.Authenticator)
		if !ok {
			return nil, &proto.Error{Code: proto.CodeProviderError, Message: fmt.Sprintf("%s does not support auth", p.Name())}
		}
		url, err := au.StartAuth(ctx)
		if err != nil {
			return nil, &proto.Error{Code: proto.CodeProviderError, Message: err.Error()}
		}
		return proto.AuthStartResult{URL: url}, nil
	})

	d.server.Handle(proto.MethodAuthStatus, func(_ context.Context, _ json.RawMessage) (any, error) {
		p := d.activeProvider()
		if p == nil {
			return proto.AuthStatus{Connected: false}, nil
		}
		au, ok := p.(providers.Authenticator)
		if !ok {
			return proto.AuthStatus{Connected: true, Provider: p.Name()}, nil
		}
		return proto.AuthStatus{Connected: au.IsAuthenticated(), Provider: p.Name()}, nil
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

func (d *Daemon) startActiveProvider(parent context.Context) {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.active == nil || d.activeRunning {
		return
	}
	ctx, cancel := context.WithCancel(parent)
	d.activeCancel = cancel
	d.activeRunning = true
	p := d.active
	go func() {
		if err := p.Run(ctx, d.machine); err != nil && !errors.Is(err, context.Canceled) {
			d.logger.Error("provider stopped", "provider", p.Name(), "err", err)
		}
		d.mu.Lock()
		if d.active == p {
			d.activeRunning = false
		}
		d.mu.Unlock()
	}()
}

func (d *Daemon) stopActiveProvider() {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.activeCancel != nil {
		d.activeCancel()
		d.activeCancel = nil
		d.activeRunning = false
	}
}

func (d *Daemon) watchProviders(ctx context.Context) {
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			d.mu.RLock()
			current := d.active
			provs := append([]providers.Provider(nil), d.providers...)
			d.mu.RUnlock()

			// Promote the first available provider that isn't stub.
			// Provider list order = priority order.
			for _, p := range provs {
				if p.Name() == current.Name() {
					break
				}
				if p.Available(ctx) {
					d.logger.Info("provider became available, switching", "from", current.Name(), "to", p.Name())
					d.stopActiveProvider()
					d.mu.Lock()
					d.active = p
					d.mu.Unlock()
					d.startActiveProvider(ctx)
					break
				}
			}
		}
	}
}
