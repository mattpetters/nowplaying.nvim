// Package spotify implements a Provider that controls the Spotify desktop
// app via osascript (AppleScript) for transport commands, and the Spotify
// Web API for search and library operations.
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
	"github.com/mpetters/nowplaying/internal/providers"
	"github.com/mpetters/nowplaying/internal/state"
)

type Provider struct {
	pollInterval time.Duration
	tokens       *tokenStore
	api          *apiClient
	auth         *authFlow
}

func New() *Provider {
	tokens := newTokenStore()
	_ = tokens.load()
	return &Provider{
		pollInterval: 1 * time.Second,
		tokens:       tokens,
		api:          newAPIClient(tokens, defaultClientID),
		auth:         newAuthFlow(defaultClientID, tokens),
	}
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
  set trackID to id of t
  set playerState to player state as string
  set pos to player position
  set dur to duration of t
  set vol to sound volume

  return trackName & "||" & artistName & "||" & albumName & "||" & playerState & "||" & pos & "||" & dur & "||" & vol & "||" & trackID
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

	parts := strings.SplitN(out, "||", 8)
	if len(parts) < 7 {
		return state.Observation{}, fmt.Errorf("unexpected osascript output: %s", out)
	}

	status := parseStatus(parts[3])
	positionSec := parseFloat(parts[4])
	durationMS := int64(parseFloat(parts[5]))
	volume := parseInt(parts[6])
	positionMS := int64(math.Round(positionSec * 1000))

	track := &proto.Track{
		Title:      parts[0],
		Artist:     parts[1],
		Album:      parts[2],
		DurationMS: durationMS,
	}
	if len(parts) >= 8 {
		uri := strings.TrimSpace(parts[7])
		track.URI = uri
		track.ID = strings.TrimPrefix(uri, "spotify:track:")
	}

	return state.Observation{
		Provider:   p.Name(),
		Status:     status,
		Track:      track,
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
	if p.api.hasTokens() {
		if err := p.api.play(uri); err == nil {
			return nil
		}
	}
	script := fmt.Sprintf(`tell application "Spotify" to play track "%s"`, uri)
	_, err := runOsa(script)
	return err
}

func (p *Provider) LikeToggle(_ context.Context, trackID string) (bool, error) {
	if trackID != "" && p.api.hasTokens() {
		saved, err := p.api.isTrackSaved(trackID)
		if err == nil {
			if saved {
				if err := p.api.removeTrack(trackID); err == nil {
					return false, nil
				}
			} else {
				if err := p.api.saveTrack(trackID); err == nil {
					return true, nil
				}
			}
		}
	}
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

func (p *Provider) Search(_ context.Context, query string, limit int) ([]providers.SearchTrack, error) {
	tracks, err := p.api.search(query, limit)
	if err != nil {
		return nil, err
	}
	out := make([]providers.SearchTrack, len(tracks))
	for i, t := range tracks {
		artists := make([]string, len(t.Artists))
		for j, a := range t.Artists {
			artists[j] = a.Name
		}
		var art string
		if len(t.Album.Images) > 0 {
			art = t.Album.Images[0].URL
		}
		out[i] = providers.SearchTrack{
			ID:         t.ID,
			URI:        t.URI,
			Title:      t.Name,
			Artist:     strings.Join(artists, ", "),
			Album:      t.Album.Name,
			DurationMS: t.DurationMS,
			ArtworkURL: art,
		}
	}
	return out, nil
}

func (p *Provider) StartAuth(ctx context.Context) (string, error) {
	return p.auth.startAndWait(ctx)
}

func (p *Provider) IsAuthenticated() bool {
	return p.tokens.hasTokens()
}

func runOsa(script string) (string, error) {
	cmd := exec.Command("osascript", "-e", script)
	out, err := cmd.Output()
	return string(out), err
}
