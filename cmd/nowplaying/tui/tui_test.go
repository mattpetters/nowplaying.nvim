package tui

import (
	"bytes"
	"context"
	"flag"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"testing"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/charmbracelet/x/exp/teatest"
	"github.com/muesli/termenv"

	"github.com/mpetters/nowplaying/internal/ipc/fakeserver"
	"github.com/mpetters/nowplaying/internal/proto"
	"github.com/mpetters/nowplaying/internal/theme"
)

// updateGoldens controls whether the test rewrites the *.golden files
// in testdata/. Run with `go test ./cmd/nowplaying/tui -update-tui` to
// refresh — `-update` collides with go test's own corpus flag.
var updateGoldens = flag.Bool("update-tui", false, "rewrite TUI golden files")

func TestMain(m *testing.M) {
	// Force a known color profile so ANSI output is byte-identical
	// across machines (developer laptop vs CI). Without this, lipgloss
	// adapts to $TERM and goldens drift.
	lipgloss.SetColorProfile(termenv.TrueColor)
	os.Exit(m.Run())
}

// TestView_Goldens snapshots Model.View() across the {state} × {theme}
// matrix. Pure rendering — no tea program, no socket — so it's fast and
// deterministic. State is set directly on the Model since the test
// shares the package.
func TestView_Goldens(t *testing.T) {
	cases := []struct {
		name  string
		theme string
		state func(m *Model)
	}{
		{
			name:  "default_disconnected",
			theme: "default",
			state: func(m *Model) {
				m.conn = false
				m.status = "disconnected: dial: nope — retrying..."
			},
		},
		{
			name:  "default_no_track",
			theme: "default",
			state: func(m *Model) {
				m.conn = true
				m.state = proto.PlayerState{
					Provider: "stub",
					Status:   proto.StatusStopped,
					Volume:   80,
				}
			},
		},
		{
			name:  "default_playing",
			theme: "default",
			state: func(m *Model) {
				m.conn = true
				m.state = playingState()
			},
		},
		{
			name:  "default_paused",
			theme: "default",
			state: func(m *Model) {
				m.conn = true
				s := playingState()
				s.Status = proto.StatusPaused
				m.state = s
			},
		},
		{
			name:  "matrix_disconnected",
			theme: "matrix",
			state: func(m *Model) {
				m.conn = false
				m.status = "disconnected: dial: nope — retrying..."
			},
		},
		{
			name:  "matrix_no_track",
			theme: "matrix",
			state: func(m *Model) {
				m.conn = true
				m.state = proto.PlayerState{
					Provider: "stub",
					Status:   proto.StatusStopped,
					Volume:   80,
				}
			},
		},
		{
			name:  "matrix_playing",
			theme: "matrix",
			state: func(m *Model) {
				m.conn = true
				m.state = playingState()
			},
		},
		{
			name:  "matrix_paused",
			theme: "matrix",
			state: func(m *Model) {
				m.conn = true
				s := playingState()
				s.Status = proto.StatusPaused
				m.state = s
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			th, err := theme.Get(tc.theme)
			if err != nil {
				t.Fatalf("theme.Get(%q): %v", tc.theme, err)
			}
			m := New(context.Background(), "/dev/null", th)
			m.width = 80
			m.height = 24
			tc.state(&m)

			out := []byte(m.View())
			compareGolden(t, tc.name+".golden", out)
		})
	}
}

// TestProgram_ConnectsAndUpdates exercises the full Bubble Tea program
// against a fakeserver: connect → state.get → push state.changed → see
// the new title in the rendered frame. This is the wire-level test;
// View_Goldens covers visual regression.
func TestProgram_ConnectsAndUpdates(t *testing.T) {
	fs := fakeserver.Start(t, proto.PlayerState{
		Provider: "fake",
		Status:   proto.StatusStopped,
		Volume:   60,
	})

	th, _ := theme.Get("default")
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	m := New(ctx, fs.Socket(), th)
	tm := teatest.NewTestModel(t, m, teatest.WithInitialTermSize(80, 24))

	// Wait for the connect command to land. The simplest signal is to
	// poll the rendered output until the "(nothing playing)" header
	// shows up, which only happens after connectedMsg.
	teatest.WaitFor(t, tm.Output(), func(b []byte) bool {
		return bytes.Contains(b, []byte("(nothing playing)"))
	}, teatest.WithDuration(3*time.Second))

	// Now push a track and confirm the title appears.
	fs.PushStateChanged(playingState())

	teatest.WaitFor(t, tm.Output(), func(b []byte) bool {
		return bytes.Contains(b, []byte("Strobe"))
	}, teatest.WithDuration(3*time.Second))

	tm.Send(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'q'}})
	tm.WaitFinished(t, teatest.WithFinalTimeout(3*time.Second))
}

func playingState() proto.PlayerState {
	return proto.PlayerState{
		Provider: "stub",
		Status:   proto.StatusPlaying,
		Volume:   72,
		Track: &proto.Track{
			Title:      "Strobe",
			Artist:     "deadmau5",
			Album:      "For Lack of a Better Name",
			DurationMS: 634000,
		},
		PositionMS: 120000,
	}
}

// compareGolden either writes or compares against testdata/<name>.
// Output is sanitized so machine-specific noise doesn't break the diff.
func compareGolden(t *testing.T, name string, got []byte) {
	t.Helper()
	got = sanitize(got)

	path := filepath.Join("testdata", name)
	if *updateGoldens {
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatalf("mkdir testdata: %v", err)
		}
		if err := os.WriteFile(path, got, 0o644); err != nil {
			t.Fatalf("write golden: %v", err)
		}
		return
	}
	want, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read golden %s: %v (run with -update to create)", path, err)
	}
	if !bytes.Equal(got, want) {
		t.Errorf("golden %s differs.\n--- got ---\n%s\n--- want ---\n%s",
			name, string(got), string(want))
	}
}

// sanitize strips bytes that aren't byte-stable across runs. So far
// nothing in View() depends on time/random data, so this is a pass-
// through — but reserving the hook keeps the test forgiving.
var ansiCSI = regexp.MustCompile(`\x1b\[[0-9;]*[A-Za-z]`)

func sanitize(b []byte) []byte {
	// Normalize line endings.
	b = bytes.ReplaceAll(b, []byte("\r\n"), []byte("\n"))
	return b
}

// drainOutput is a small helper used by ad-hoc tests that want to peek
// at the program's screen without waiting for it to finish.
func drainOutput(r io.Reader, max int) []byte {
	buf := make([]byte, max)
	n, _ := r.Read(buf)
	return buf[:n]
}

var _ = ansiCSI // reserved for future sanitizer use
var _ = drainOutput
