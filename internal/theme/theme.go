// Package theme defines the TUI's color palette and the artwork filter
// pipeline tied to it. A Theme is a client-side UX preference; the
// daemon does not know about it.
package theme

import (
	"fmt"

	"github.com/mpetters/nowplaying/internal/artwork/filter"
)

// Palette is the set of colors a theme exposes. All values are hex
// strings (e.g. "#00ff41") so they can be marshaled to TOML and handed
// to lipgloss as lipgloss.Color.
type Palette struct {
	FG     string
	BG     string
	Accent string
	Dim    string
	Border string
	Muted  string
}

// Theme bundles a palette with the artwork pipeline that should run
// against album art when the theme is active.
type Theme struct {
	Name    string
	Palette Palette
	Artwork filter.Pipeline
}

// Get returns the theme registered under name, or an error.
func Get(name string) (Theme, error) {
	t, ok := registry[name]
	if !ok {
		return Theme{}, fmt.Errorf("unknown theme: %s", name)
	}
	return t, nil
}

// Names returns all registered theme names in registration order.
func Names() []string {
	out := make([]string, len(order))
	copy(out, order)
	return out
}

// Next returns the name of the theme after current in cycle order.
// If current isn't registered, returns the first registered theme.
func Next(current string) string {
	for i, n := range order {
		if n == current {
			return order[(i+1)%len(order)]
		}
	}
	if len(order) > 0 {
		return order[0]
	}
	return ""
}

var (
	registry = map[string]Theme{}
	order    []string
)

// register adds a theme to the registry. Used by presets.go init().
func register(t Theme) {
	if _, exists := registry[t.Name]; !exists {
		order = append(order, t.Name)
	}
	registry[t.Name] = t
}
