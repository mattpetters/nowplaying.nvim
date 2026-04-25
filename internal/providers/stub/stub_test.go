package stub

import (
	"context"
	"testing"
	"time"

	"github.com/mpetters/nowplaying/internal/proto"
	"github.com/mpetters/nowplaying/internal/state"
)

func TestStubProvider_PublishesObservations(t *testing.T) {
	p := New()
	p.tick = 20 * time.Millisecond
	m := state.NewMachine()
	id, ch := m.Subscribe(64)
	defer m.Unsubscribe(id)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go func() { _ = p.Run(ctx, m) }()

	deadline := time.After(2 * time.Second)
	var sawState bool
	for !sawState {
		select {
		case n := <-ch:
			if n.Method == proto.NotifyStateChanged {
				sawState = true
			}
		case <-deadline:
			t.Fatal("did not see state.changed within deadline")
		}
	}
}

func TestStubProvider_TransportCommands(t *testing.T) {
	p := New()
	ctx := context.Background()
	if err := p.Pause(ctx); err != nil {
		t.Fatal(err)
	}
	if err := p.Next(ctx); err != nil {
		t.Fatal(err)
	}
	if err := p.SetVolume(ctx, 250); err != nil {
		t.Fatal(err)
	}
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.status != proto.StatusPaused {
		t.Errorf("status = %s", p.status)
	}
	if p.track.ID != "stub-2" {
		t.Errorf("track id = %s", p.track.ID)
	}
	if p.volume != 100 {
		t.Errorf("volume clamp = %d", p.volume)
	}
}
