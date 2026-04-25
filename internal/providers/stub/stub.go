// Package stub is an in-memory provider used by the daemon's smoke
// tests and Phase 1 development. It produces synthetic state changes on
// a tick so the IPC + state pipeline can be exercised without a real
// music app.
package stub

import (
	"context"
	"sync"
	"time"

	"github.com/mpetters/nowplaying/internal/proto"
	"github.com/mpetters/nowplaying/internal/state"
)

type Provider struct {
	mu     sync.Mutex
	status proto.Status
	track  *proto.Track
	pos    int64
	volume int
	tick   time.Duration
}

func New() *Provider {
	return &Provider{
		status: proto.StatusPlaying,
		track: &proto.Track{
			ID:         "stub-1",
			Title:      "Sample Track",
			Artist:     "Sample Artist",
			Album:      "Sample Album",
			DurationMS: 200000,
		},
		volume: 60,
		tick:   500 * time.Millisecond,
	}
}

func (p *Provider) Name() string                          { return "stub" }
func (p *Provider) Available(_ context.Context) bool      { return true }

func (p *Provider) Run(ctx context.Context, m *state.Machine) error {
	t := time.NewTicker(p.tick)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-t.C:
			p.advance()
			p.mu.Lock()
			obs := state.Observation{
				Provider:   p.Name(),
				Status:     p.status,
				Track:      cloneTrack(p.track),
				Volume:     p.volume,
				PositionMS: p.pos,
			}
			p.mu.Unlock()
			m.Apply(obs)
		}
	}
}

func (p *Provider) Play(_ context.Context) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.status = proto.StatusPlaying
	return nil
}

func (p *Provider) Pause(_ context.Context) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.status = proto.StatusPaused
	return nil
}

func (p *Provider) Next(_ context.Context) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.track = &proto.Track{
		ID:         "stub-2",
		Title:      "Next Track",
		Artist:     p.track.Artist,
		Album:      p.track.Album,
		DurationMS: 240000,
	}
	p.pos = 0
	return nil
}

func (p *Provider) Prev(_ context.Context) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.pos = 0
	return nil
}

func (p *Provider) Seek(_ context.Context, ms int64) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.pos = ms
	return nil
}

func (p *Provider) SetVolume(_ context.Context, level int) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	if level < 0 {
		level = 0
	}
	if level > 100 {
		level = 100
	}
	p.volume = level
	return nil
}

func (p *Provider) advance() {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.status != proto.StatusPlaying || p.track == nil {
		return
	}
	p.pos += int64(p.tick / time.Millisecond)
	if p.pos >= p.track.DurationMS {
		p.pos = 0
	}
}

func cloneTrack(t *proto.Track) *proto.Track {
	if t == nil {
		return nil
	}
	c := *t
	return &c
}
