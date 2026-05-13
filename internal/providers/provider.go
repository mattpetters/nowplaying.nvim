// Package providers defines the contract every music source implements.
// The daemon multiplexes one or more providers; the state machine merges
// their observations into the canonical PlayerState.
package providers

import (
	"context"

	"github.com/mpetters/nowplaying/internal/state"
)

// Provider is implemented by Apple Music, Spotify, macOS Media, and the
// stub used in tests.
type Provider interface {
	// Name is a stable identifier (e.g. "spotify", "apple_music").
	Name() string

	// Available reports whether this provider can be used right now.
	// For Apple Music: app installed and reachable. For Spotify:
	// tokens present and not expired.
	Available(ctx context.Context) bool

	// Run polls the provider until ctx is canceled, publishing
	// observations to the state machine. Returning a non-nil error
	// signals an unrecoverable failure; the daemon decides whether to
	// restart or surface to clients.
	Run(ctx context.Context, m *state.Machine) error

	// Play, Pause, Next, Prev, Seek, Volume are transport commands.
	// Each call should be idempotent and best-effort.
	Play(ctx context.Context) error
	Pause(ctx context.Context) error
	Next(ctx context.Context) error
	Prev(ctx context.Context) error
	Seek(ctx context.Context, ms int64) error
	SetVolume(ctx context.Context, level int) error
}

// URIPlayer is optionally implemented by providers that can play a
// specific track/search URI (e.g. "spotify:track:..." or "spotify:search:...").
type URIPlayer interface {
	PlayURI(ctx context.Context, uri string) error
}

// Liker is optionally implemented by providers that support
// liking/unliking the currently playing track.
type Liker interface {
	LikeToggle(ctx context.Context) (liked bool, err error)
}
