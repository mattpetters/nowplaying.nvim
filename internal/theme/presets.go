package theme

import "github.com/mpetters/nowplaying/internal/artwork/filter"

// DefaultName is the theme used when nothing is configured.
const DefaultName = "default"

func init() {
	register(Theme{
		Name: "default",
		Palette: Palette{
			FG:     "#d4d4d4",
			BG:     "",        // empty = terminal default
			Accent: "#1ed760", // Spotify green
			Dim:    "#7a7a7a",
			Border: "#3a3a3a",
			Muted:  "#5a5a5a",
		},
		Artwork: nil, // identity pipeline
	})

	// matrix: mactop "lime" aesthetic — sage green on black, muted phosphor.
	// FG is the soft lime mactop uses for text/borders; Accent is the
	// slightly brighter shade it uses for filled bar fills; Dim/Muted
	// are darker shades for de-emphasized text and progress troughs.
	register(Theme{
		Name: "matrix",
		Palette: Palette{
			FG:     "#a8c989",
			BG:     "#000000",
			Accent: "#b8d49a",
			Dim:    "#6b8454",
			Border: "#5a7142",
			Muted:  "#3d4f2b",
		},
		Artwork: filter.Pipeline{
			filter.Downsample{Size: 64},
			filter.Desaturate{},
			filter.HexTint("#a8c989"),
			filter.Dither{Levels: 4},
		},
	})
}
