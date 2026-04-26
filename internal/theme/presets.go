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

	register(Theme{
		Name: "matrix",
		Palette: Palette{
			FG:     "#00ff41",
			BG:     "#000000",
			Accent: "#00ff41",
			Dim:    "#008f11",
			Border: "#003b00",
			Muted:  "#005f0a",
		},
		Artwork: filter.Pipeline{
			filter.Downsample{Size: 64},
			filter.Desaturate{},
			filter.HexTint("#00ff41"),
			filter.Dither{Levels: 4},
		},
	})
}
