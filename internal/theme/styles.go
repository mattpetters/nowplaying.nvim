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
//
// We deliberately do NOT paint the theme background onto every text
// style — that ends up filling pad areas with the BG color and looks
// like a highlighted bar. Foreground colors only; the terminal/tmux
// pane shows through. BG is reserved for explicit canvases (artwork
// matting, banners) that opt in by referencing Base.
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
		Title:    lipgloss.NewStyle().Foreground(accent).Bold(true),
		Artist:   lipgloss.NewStyle().Foreground(fg),
		Album:    lipgloss.NewStyle().Foreground(dim).Italic(true),
		Status:   lipgloss.NewStyle().Foreground(accent),
		Progress: lipgloss.NewStyle().Foreground(accent),
		Track:    lipgloss.NewStyle().Foreground(muted),
		Hint:     lipgloss.NewStyle().Foreground(dim),
		Banner:   lipgloss.NewStyle().Foreground(accent).Bold(true),
	}
}
