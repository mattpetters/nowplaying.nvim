package theme

import "github.com/charmbracelet/lipgloss"

// Styles is the bundle of every lipgloss.Style the TUI uses. Derived
// once from a Theme and passed to the model — there are no hardcoded
// colors anywhere in cmd/nowplaying.
type Styles struct {
	Base     lipgloss.Style
	Border   lipgloss.Style
	Title    lipgloss.Style
	Artist   lipgloss.Style
	Album    lipgloss.Style
	Status   lipgloss.Style
	Progress lipgloss.Style // filled portion of progress bar
	Track    lipgloss.Style // unfilled portion
	Hint     lipgloss.Style
	Banner   lipgloss.Style
}

// Build derives a Styles set from t.
func Build(t Theme) Styles {
	fg := lipgloss.Color(t.Palette.FG)
	accent := lipgloss.Color(t.Palette.Accent)
	dim := lipgloss.Color(t.Palette.Dim)
	border := lipgloss.Color(t.Palette.Border)
	muted := lipgloss.Color(t.Palette.Muted)

	base := lipgloss.NewStyle().Foreground(fg)
	if t.Palette.BG != "" {
		base = base.Background(lipgloss.Color(t.Palette.BG))
	}

	return Styles{
		Base: base,
		Border: lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(border).
			Padding(0, 1),
		Title:    base.Bold(true).Foreground(accent),
		Artist:   base.Foreground(fg),
		Album:    base.Foreground(dim).Italic(true),
		Status:   base.Foreground(accent).Bold(true),
		Progress: lipgloss.NewStyle().Foreground(accent),
		Track:    lipgloss.NewStyle().Foreground(muted),
		Hint:     base.Foreground(dim),
		Banner:   base.Foreground(accent).Bold(true),
	}
}
