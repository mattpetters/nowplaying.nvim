// Package spotify implements a Provider that controls the Spotify desktop
// app via osascript (AppleScript). No auth or network calls — it shells
// out to the local Spotify process, so it works whenever Spotify.app is
// running.
package spotify

import (
	"context"
	"fmt"
	"math"
	"os/exec"
	"strconv"
	"strings"
	"time"

	"github.com/mpetters/nowplaying/internal/proto"
	"github.com/mpetters/nowplaying/internal/state"
)

type Provider struct {
	pollInterval time.Duration
}

func New() *Provider {
	return &Provider{pollInterval: 1 * time.Second}
}

func (p *Provider) Name() string { return "spotify" }

func (p *Provider) Available(_ context.Context) bool {
	out, err := runOsa(`tell application "System Events" to (name of processes) contains "Spotify"`)
	return err == nil && strings.TrimSpace(out) == "true"
}

func (p *Provider) Run(ctx context.Context, m *state.Machine) error {
	t := time.NewTicker(p.pollInterval)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-t.C:
			obs, err := p.poll()
			if err != nil {
				continue
			}
			m.Apply(obs)
		}
	}
}

func (p *Provider) Play(_ context.Context) error {
	_, err := runOsa(`tell application "Spotify" to play`)
	return err
}

func (p *Provider) Pause(_ context.Context) error {
	_, err := runOsa(`tell application "Spotify" to pause`)
	return err
}

func (p *Provider) Next(_ context.Context) error {
	_, err := runOsa(`tell application "Spotify" to next track`)
	return err
}

func (p *Provider) Prev(_ context.Context) error {
	_, err := runOsa(`tell application "Spotify" to previous track`)
	return err
}

func (p *Provider) Seek(_ context.Context, ms int64) error {
	secs := float64(ms) / 1000.0
	script := fmt.Sprintf(`tell application "Spotify" to set player position to %f`, secs)
	_, err := runOsa(script)
	return err
}

func (p *Provider) SetVolume(_ context.Context, level int) error {
	if level < 0 {
		level = 0
	}
	if level > 100 {
		level = 100
	}
	script := fmt.Sprintf(`tell application "Spotify" to set sound volume to %d`, level)
	_, err := runOsa(script)
	return err
}

const statusScript = `
tell application "Spotify"
  if player state is stopped then
    return "inactive"
  end if

  set t to current track
  set trackName to name of t
  set artistName to artist of t
  set albumName to album of t
  set playerState to player state as string
  set pos to player position
  set dur to duration of t
  set vol to sound volume

  return trackName & "||" & artistName & "||" & albumName & "||" & playerState & "||" & pos & "||" & dur & "||" & vol
end tell
`

func (p *Provider) poll() (state.Observation, error) {
	out, err := runOsa(statusScript)
	if err != nil {
		return state.Observation{}, err
	}

	out = strings.TrimSpace(out)
	if out == "inactive" {
		return state.Observation{
			Provider:  p.Name(),
			Status:    proto.StatusStopped,
			SampledAt: time.Now(),
		}, nil
	}

	parts := strings.SplitN(out, "||", 7)
	if len(parts) < 7 {
		return state.Observation{}, fmt.Errorf("unexpected osascript output: %s", out)
	}

	status := parseStatus(parts[3])
	positionSec := parseFloat(parts[4]) // AppleScript: seconds
	durationMS := int64(parseFloat(parts[5])) // AppleScript: milliseconds
	volume := parseInt(parts[6])
	positionMS := int64(math.Round(positionSec * 1000))

	return state.Observation{
		Provider: p.Name(),
		Status:   status,
		Track: &proto.Track{
			Title:      parts[0],
			Artist:     parts[1],
			Album:      parts[2],
			DurationMS: durationMS,
		},
		Volume:     volume,
		PositionMS: positionMS,
		SampledAt:  time.Now(),
	}, nil
}

func parseStatus(s string) proto.Status {
	switch strings.TrimSpace(strings.ToLower(s)) {
	case "playing":
		return proto.StatusPlaying
	case "paused":
		return proto.StatusPaused
	default:
		return proto.StatusStopped
	}
}

func parseFloat(s string) float64 {
	s = strings.TrimSpace(s)
	s = strings.ReplaceAll(s, ",", ".")
	f, _ := strconv.ParseFloat(s, 64)
	return f
}

func parseInt(s string) int {
	s = strings.TrimSpace(s)
	n, _ := strconv.Atoi(s)
	return n
}

func (p *Provider) PlayURI(_ context.Context, uri string) error {
	script := fmt.Sprintf(`tell application "Spotify" to play track "%s"`, uri)
	_, err := runOsa(script)
	return err
}

func (p *Provider) LikeToggle(_ context.Context) (bool, error) {
	// Spotify AppleScript has no direct like API. Use System Events to
	// click Song → Like in the menu bar. Returns true optimistically.
	script := `
tell application "System Events"
  tell process "Spotify"
    set frontmost to true
    delay 0.1
    click menu item "Like" of menu "Song" of menu bar 1
  end tell
end tell
return "ok"
`
	_, err := runOsa(script)
	return true, err
}

func runOsa(script string) (string, error) {
	cmd := exec.Command("osascript", "-e", script)
	out, err := cmd.Output()
	return string(out), err
}
