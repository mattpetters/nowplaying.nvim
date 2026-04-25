package state

import (
	"testing"
	"time"

	"github.com/mpetters/nowplaying/internal/proto"
)

func TestApply_FirstObservationEmitsAllThree(t *testing.T) {
	m := NewMachine()
	notifs := m.Apply(Observation{
		Provider: "spotify",
		Status:   proto.StatusPlaying,
		Track:    &proto.Track{ID: "t1", Title: "A", Artist: "B", DurationMS: 200000},
		Volume:   50,
	})
	wantMethods := []string{
		proto.NotifyTrackChanged,
		proto.NotifyStateChanged,
		proto.NotifyProgressTick,
	}
	assertMethods(t, notifs, wantMethods)
}

func TestApply_NoChangeNoNotification(t *testing.T) {
	m := NewMachine()
	obs := Observation{
		Provider: "spotify",
		Status:   proto.StatusPaused, // not playing → no progress tick
		Track:    &proto.Track{ID: "t1", Title: "A", Artist: "B", DurationMS: 200000},
		Volume:   50,
	}
	_ = m.Apply(obs)
	notifs := m.Apply(obs) // identical
	if len(notifs) != 0 {
		t.Fatalf("expected zero notifications, got %d (%+v)", len(notifs), notifs)
	}
}

func TestApply_TrackChangeEmitsTrackAndState(t *testing.T) {
	m := NewMachine()
	_ = m.Apply(Observation{
		Provider: "spotify",
		Status:   proto.StatusPlaying,
		Track:    &proto.Track{ID: "t1", Title: "A", Artist: "B", DurationMS: 200000},
	})
	notifs := m.Apply(Observation{
		Provider: "spotify",
		Status:   proto.StatusPlaying,
		Track:    &proto.Track{ID: "t2", Title: "C", Artist: "D", DurationMS: 180000},
	})
	wantMethods := []string{
		proto.NotifyTrackChanged,
		proto.NotifyStateChanged,
		proto.NotifyProgressTick,
	}
	assertMethods(t, notifs, wantMethods)

	for _, n := range notifs {
		if n.Method == proto.NotifyTrackChanged {
			tc := n.Body.(proto.TrackChanged)
			if tc.Prev == nil || tc.Prev.ID != "t1" || tc.Current.ID != "t2" {
				t.Errorf("track change body wrong: %+v", tc)
			}
		}
	}
}

func TestApply_PositionTickWhilePlaying(t *testing.T) {
	m := NewMachine()
	_ = m.Apply(Observation{
		Provider: "spotify",
		Status:   proto.StatusPlaying,
		Track:    &proto.Track{ID: "t1", DurationMS: 200000},
		PositionMS: 1000,
	})
	notifs := m.Apply(Observation{
		Provider: "spotify",
		Status:   proto.StatusPlaying,
		Track:    &proto.Track{ID: "t1", DurationMS: 200000},
		PositionMS: 2000,
	})
	// Same renderable state (status/track/volume identical), so no
	// state.changed — but progress.tick must fire.
	assertMethods(t, notifs, []string{proto.NotifyProgressTick})
}

func TestApply_DebouncesAfterTransportCommand(t *testing.T) {
	now := time.Unix(1700000000, 0)
	m := NewMachine()
	m.SetClock(func() time.Time { return now })
	m.MarkCommandIssued()

	// Same instant: command in flight, observation gets dropped.
	notifs := m.Apply(Observation{
		Provider: "spotify",
		Status:   proto.StatusPlaying,
		Track:    &proto.Track{ID: "t1", DurationMS: 200000},
	})
	if len(notifs) != 0 {
		t.Fatalf("expected drop during debounce window, got %+v", notifs)
	}

	// Advance past the 250ms debounce window.
	now = now.Add(300 * time.Millisecond)
	notifs = m.Apply(Observation{
		Provider: "spotify",
		Status:   proto.StatusPlaying,
		Track:    &proto.Track{ID: "t1", DurationMS: 200000},
	})
	if len(notifs) == 0 {
		t.Fatal("expected notifications after debounce window")
	}
}

func TestSubscribe_FanOut(t *testing.T) {
	m := NewMachine()
	id1, ch1 := m.Subscribe(8)
	id2, ch2 := m.Subscribe(8)
	defer m.Unsubscribe(id1)
	defer m.Unsubscribe(id2)

	m.Apply(Observation{
		Provider: "spotify",
		Status:   proto.StatusPlaying,
		Track:    &proto.Track{ID: "t1", DurationMS: 1000},
	})

	for _, ch := range []<-chan Notification{ch1, ch2} {
		var got []string
		timeout := time.After(time.Second)
	loop:
		for len(got) < 3 {
			select {
			case n := <-ch:
				got = append(got, n.Method)
			case <-timeout:
				break loop
			}
		}
		if len(got) != 3 {
			t.Fatalf("subscriber missed notifications, got %v", got)
		}
	}
}

func TestSubscribe_DropsForSlowSubscriber(t *testing.T) {
	m := NewMachine()
	_, ch := m.Subscribe(1) // tiny buffer
	defer func() {
		// drain to allow Unsubscribe to close cleanly
		select {
		case <-ch:
		default:
		}
	}()

	// Many observations — buffer can only hold one notification
	// before drops kick in.
	for i := range 10 {
		m.Apply(Observation{
			Provider: "spotify",
			Status:   proto.StatusPlaying,
			Track:    &proto.Track{ID: "t1", DurationMS: 1000},
			PositionMS: int64(i * 100),
		})
	}
	// We don't read the channel — the test asserts that Apply did not
	// block. If we got here, fan-out used non-blocking sends.
}

func TestEmit_ArbitraryNotification(t *testing.T) {
	m := NewMachine()
	id, ch := m.Subscribe(4)
	defer m.Unsubscribe(id)
	m.Emit(Notification{
		Method: proto.NotifyAuthRequired,
		Body:   proto.AuthRequired{Provider: "spotify"},
	})
	select {
	case n := <-ch:
		if n.Method != proto.NotifyAuthRequired {
			t.Errorf("got %s", n.Method)
		}
	case <-time.After(time.Second):
		t.Fatal("timeout waiting for emit")
	}
}

func assertMethods(t *testing.T, notifs []Notification, want []string) {
	t.Helper()
	if len(notifs) != len(want) {
		t.Fatalf("got %d notifs, want %d: %+v", len(notifs), len(want), methods(notifs))
	}
	for i, m := range want {
		if notifs[i].Method != m {
			t.Errorf("notif[%d] = %q, want %q", i, notifs[i].Method, m)
		}
	}
}

func methods(notifs []Notification) []string {
	out := make([]string, len(notifs))
	for i, n := range notifs {
		out[i] = n.Method
	}
	return out
}
