// Package state owns the canonical PlayerState. Provider goroutines
// publish observations via Apply, and clients subscribe to notifications
// derived from state transitions.
//
// The state machine is deliberately small: provider observations come in,
// canonical state is updated, and zero-or-more notifications go out. All
// I/O lives in the daemon's IPC layer; this package is pure reducer +
// pub/sub.
package state

import (
	"sync"
	"time"

	"github.com/mpetters/nowplaying/internal/proto"
)

// Observation is what a provider reports.
type Observation struct {
	Provider   string
	Status     proto.Status
	Track      *proto.Track
	Volume     int
	PositionMS int64
	// SampledAt is when the provider read this state. Defaults to now if zero.
	SampledAt time.Time
}

// Notification is a typed event emitted by the state machine.
type Notification struct {
	Method string // proto.Notify*
	Body   any
}

// Machine is the canonical state holder.
type Machine struct {
	mu          sync.RWMutex
	state       proto.PlayerState
	subscribers map[int]chan Notification
	nextSubID   int
	// debounce keeps recent transport commands so we ignore stale provider
	// state that arrives right after a command flips the player.
	lastCmdAt time.Time
	clock     func() time.Time
}

func NewMachine() *Machine {
	return &Machine{
		subscribers: make(map[int]chan Notification),
		clock:       time.Now,
	}
}

// SetClock overrides the wall clock for tests.
func (m *Machine) SetClock(c func() time.Time) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.clock = c
}

// Get returns a copy of the current canonical state.
func (m *Machine) Get() proto.PlayerState {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return cloneState(m.state)
}

// Apply ingests a provider observation and returns the notifications it
// produced. Notifications are also fanned out to subscribers.
func (m *Machine) Apply(obs Observation) []Notification {
	m.mu.Lock()
	defer m.mu.Unlock()

	now := m.clock()
	sampled := obs.SampledAt
	if sampled.IsZero() {
		sampled = now
	}

	// Drop observations that arrived right after a transport command.
	// They reflect the pre-command state and would cause a visible bounce.
	if !m.lastCmdAt.IsZero() && sampled.Sub(m.lastCmdAt) < 0 {
		return nil
	}
	if !m.lastCmdAt.IsZero() && now.Sub(m.lastCmdAt) < 250*time.Millisecond {
		// Fresh command in flight; skip until things settle.
		return nil
	}

	prev := cloneState(m.state)
	next := prev
	next.Provider = obs.Provider
	next.Status = obs.Status
	next.Volume = obs.Volume
	next.PositionMS = obs.PositionMS
	next.UpdatedAt = sampled.UnixMilli()
	if obs.Track != nil {
		t := *obs.Track
		next.Track = &t
	} else {
		next.Track = nil
	}

	var notifs []Notification

	if !sameTrack(prev.Track, next.Track) {
		notifs = append(notifs, Notification{
			Method: proto.NotifyTrackChanged,
			Body: proto.TrackChanged{
				Prev:    prev.Track,
				Current: next.Track,
			},
		})
	}

	if !sameRenderableState(prev, next) {
		notifs = append(notifs, Notification{
			Method: proto.NotifyStateChanged,
			Body:   cloneState(next),
		})
	}

	if next.Status == proto.StatusPlaying && next.Track != nil {
		notifs = append(notifs, Notification{
			Method: proto.NotifyProgressTick,
			Body: proto.ProgressTick{
				PositionMS: next.PositionMS,
				DurationMS: next.Track.DurationMS,
				TS:         sampled.UnixMilli(),
			},
		})
	}

	m.state = next
	m.fanOut(notifs)
	return notifs
}

// MarkCommandIssued records that a transport command was sent. Used to
// suppress stale provider observations briefly afterwards.
func (m *Machine) MarkCommandIssued() {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.lastCmdAt = m.clock()
}

// Emit publishes an arbitrary notification (e.g. auth.required, error).
func (m *Machine) Emit(n Notification) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.fanOut([]Notification{n})
}

// Subscribe registers a channel for notifications. The returned id is
// passed to Unsubscribe.
//
// Channels are buffered; if a subscriber is slow, notifications are
// dropped for that subscriber (we never block the state machine).
func (m *Machine) Subscribe(buffer int) (int, <-chan Notification) {
	if buffer <= 0 {
		buffer = 16
	}
	ch := make(chan Notification, buffer)
	m.mu.Lock()
	defer m.mu.Unlock()
	id := m.nextSubID
	m.nextSubID++
	m.subscribers[id] = ch
	return id, ch
}

func (m *Machine) Unsubscribe(id int) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if ch, ok := m.subscribers[id]; ok {
		close(ch)
		delete(m.subscribers, id)
	}
}

func (m *Machine) fanOut(ns []Notification) {
	for _, n := range ns {
		for _, ch := range m.subscribers {
			select {
			case ch <- n:
			default:
				// Drop for slow subscribers.
			}
		}
	}
}

func cloneState(s proto.PlayerState) proto.PlayerState {
	if s.Track != nil {
		t := *s.Track
		s.Track = &t
	}
	return s
}

func sameTrack(a, b *proto.Track) bool {
	switch {
	case a == nil && b == nil:
		return true
	case a == nil || b == nil:
		return false
	}
	if a.ID != "" || b.ID != "" {
		return a.ID == b.ID
	}
	// Fallback: providers without stable IDs (Apple Music) use title+artist.
	return a.Title == b.Title && a.Artist == b.Artist && a.Album == b.Album
}

// sameRenderableState reports whether two states would render identically
// to a client (ignoring fast-moving fields like PositionMS and UpdatedAt).
func sameRenderableState(a, b proto.PlayerState) bool {
	if a.Provider != b.Provider || a.Status != b.Status || a.Volume != b.Volume {
		return false
	}
	return sameTrack(a.Track, b.Track)
}
