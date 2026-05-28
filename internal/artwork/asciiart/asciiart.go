// Package asciiart converts images to ASCII art and generates procedural
// frame animations from a single source image. Zero external dependencies.
//
// # Core Types
//
//   - Frame: a single ASCII grid with a per-frame delay hint
//   - Config: controls grid dimensions, characters, and animation speed
//
// # Basic Usage
//
//	img, _ := png.Decode(reader)               // any image.Image
//	cfg := asciiart.DefaultConfig(80, 24)       // 80-col x 24-row terminal
//	frames := asciiart.Animate(img, cfg)        // slice of animated frames
//	for _, f := range frames {
//	    for _, row := range f.Grid {
//	        fmt.Println(row)
//	    }
//	    time.Sleep(f.Delay)
//	}
//
// # Output Format
//
// The package can serialize/deserialize animation sets as NDJSON ("eikon"
// format, compatible with risomorphism-1911's eikon spec). Use EncodeEikon
// and DecodeEikon for persistence and caching.
//
// # Module Identity
//
// This package was extracted from the nowplaying.nvim project and published
// as github.com/mpetters/asciiart. The canonical source lives in
// internal/artwork/asciiart/ within the nowplaying.nvim repo.
package asciiart

import (
	"image"
	"math"
	"strings"
)

// Frame is a single ASCII art frame with an associated delay.
type Frame struct {
	Grid  []string   // each string is one row of characters, all same length
	Delay int        // milliseconds until next frame (0 = use animator default)
	Info  FrameInfo  `json:",omitempty"` // optional metadata for serialization
}

// FrameInfo carries render-time metadata.
type FrameInfo struct {
	Index int // 0-based frame index in the animation sequence
}

// Config controls the ASCII art conversion and animation pipeline.
type Config struct {
	// Width and Height are the character-cell dimensions of the output grid.
	Width  int
	Height int

	// Charset is the string of characters used for intensity mapping, from
	// darkest (index 0) to brightest. See StandardCharset, DenseCharset, etc.
	Charset string

	// FramesPerSecond controls animation speed.
	FramesPerSecond float64

	// Scale is the initial image scale factor (1.0 = fill grid tightly).
	// Lower values show more of the image (letterbox), higher values crop in.
	Scale float64

	// FocalX, FocalY define the center point for zoom/pan effects, in
	// normalized image coordinates (0-1). Default 0.5, 0.5.
	FocalX, FocalY float64

	// Invert flips the intensity mapping so light pixels map to dark chars.
	Invert bool

	// Motion controls which animation preset to use.
	Motion MotionPreset

	// FrameCount is the total frames to generate. 0 = auto (based on FPS).
	FrameCount int
}

// MotionPreset selects an animation style.
type MotionPreset int

const (
	MotionStill   MotionPreset = iota // single frame, no animation
	MotionZoomIn                      // slow Ken Burns zoom
	MotionPulse                       // brightness oscillation
	MotionScan                        // horizontal scan reveal
	MotionRipple                      // sine-wave row distortion
	MotionGlitch                      // random column shifts
	MotionDissolve                    // crossfade between charsets
	MotionBreath                      // subtle scale pulse
	MotionOrbit                       // focal point rotation
)

// MotionPreset names for serialization.
var motionNames = map[MotionPreset]string{
	MotionStill:   "still",
	MotionZoomIn:  "zoom",
	MotionPulse:   "pulse",
	MotionScan:    "scan",
	MotionRipple:  "ripple",
	MotionGlitch:  "glitch",
	MotionDissolve: "dissolve",
	MotionBreath:  "breath",
	MotionOrbit:   "orbit",
}

func (m MotionPreset) String() string {
	if s, ok := motionNames[m]; ok {
		return s
	}
	return "still"
}

// ParseMotionPreset converts a string name to a MotionPreset.
func ParseMotionPreset(s string) MotionPreset {
	for k, v := range motionNames {
		if v == s {
			return k
		}
	}
	return MotionStill
}

// DefaultConfig returns a Config with sensible defaults for a terminal of
// the given character dimensions.
func DefaultConfig(width, height int) Config {
	return Config{
		Width:           width,
		Height:          height,
		Charset:         StandardCharset,
		FramesPerSecond: 8,
		Scale:           1.0,
		FocalX:          0.5,
		FocalY:          0.5,
		Invert:          false,
		Motion:          MotionZoomIn,
		FrameCount:      0, // auto
	}
}

// autoFrameCount returns a reasonable number of frames for the config.
func (cfg Config) autoFrameCount() int {
	if cfg.FrameCount > 0 {
		return cfg.FrameCount
	}
	// Default: ~3 seconds of animation
	return int(math.Ceil(cfg.FramesPerSecond * 3))
}

// autoDelay returns the per-frame delay in ms.
func (cfg Config) autoDelay() int {
	return int(math.Round(1000.0 / cfg.FramesPerSecond))
}

// ─── Pixel types ─────────────────────────────────────────────────────────

// Pixel represents a single pixel's grayscale value and color.
type Pixel struct {
	Gray    uint8 // 0-255 grayscale value
	R, G, B uint8 // original color
	A       uint8 // alpha
}

// Grid is a 2D array of pixels ready for ASCII mapping.
type Grid [][]Pixel

// ToASCII converts a Grid to a slice of strings using the given charset.
// Each pixel maps to a character based on its grayscale intensity.
func (g Grid) ToASCII(charset string, invert bool) []string {
	if len(g) == 0 || len(g[0]) == 0 {
		return nil
	}
	rows := make([]string, len(g))
	clen := len(charset)
	if clen == 0 {
		clen = 1
	}
	for y, row := range g {
		buf := make([]byte, len(row))
		for x, p := range row {
			gray := p.Gray
			if invert {
				gray = 255 - gray
			}
			idx := int(gray) * (clen - 1) / 255
			if idx >= clen {
				idx = clen - 1
			}
			buf[x] = charset[idx]
		}
		rows[y] = string(buf)
	}
	return rows
}

// ToGrayscale converts an image.Image to a Grid, resizing to the given
// dimensions using nearest-neighbor sampling.
func ToGrayscale(img image.Image, width, height int) Grid {
	srcBounds := img.Bounds()
	srcW := srcBounds.Dx()
	srcH := srcBounds.Dy()

	if srcW == 0 || srcH == 0 {
		return nil
	}

	grid := make(Grid, height)
	for y := 0; y < height; y++ {
		row := make([]Pixel, width)
		for x := 0; x < width; x++ {
			sx := x * srcW / width
			sy := y * srcH / height

			r, g, b, a := img.At(sx+srcBounds.Min.X, sy+srcBounds.Min.Y).RGBA()
			r8 := uint8(r >> 8)
			g8 := uint8(g >> 8)
			b8 := uint8(b >> 8)
			a8 := uint8(a >> 8)
			gray := uint8((int(r8) + int(g8) + int(b8)) / 3)

			row[x] = Pixel{Gray: gray, R: r8, G: g8, B: b8, A: a8}
		}
		grid[y] = row
	}
	return grid
}

// CropRect defines a sub-rectangle of the image to convert, in normalized
// coordinates (0-1).
type CropRect struct {
	X, Y, W, H float64
}

// ToGrayscaleCrop converts a cropped region of an image to a Grid.
func ToGrayscaleCrop(img image.Image, width, height int, crop CropRect) Grid {
	srcBounds := img.Bounds()
	srcW := float64(srcBounds.Dx())
	srcH := float64(srcBounds.Dy())

	if srcW == 0 || srcH == 0 {
		return nil
	}

	cropX := int(crop.X * srcW)
	cropY := int(crop.Y * srcH)
	cropW := int(crop.W * srcW)
	cropH := int(crop.H * srcH)

	if cropW <= 0 {
		cropW = int(srcW)
	}
	if cropH <= 0 {
		cropH = int(srcH)
	}

	grid := make(Grid, height)
	for y := 0; y < height; y++ {
		row := make([]Pixel, width)
		for x := 0; x < width; x++ {
			sx := cropX + x*cropW/width
			sy := cropY + y*cropH/height

			if sx >= srcBounds.Max.X {
				sx = srcBounds.Max.X - 1
			}
			if sy >= srcBounds.Max.Y {
				sy = srcBounds.Max.Y - 1
			}

			r, g, b, a := img.At(sx, sy).RGBA()
			r8 := uint8(r >> 8)
			g8 := uint8(g >> 8)
			b8 := uint8(b >> 8)
			a8 := uint8(a >> 8)
			gray := uint8((int(r8) + int(g8) + int(b8)) / 3)

			row[x] = Pixel{Gray: gray, R: r8, G: g8, B: b8, A: a8}
		}
		grid[y] = row
	}
	return grid
}

// FrameFromImage renders a single still frame from an image.
func FrameFromImage(img image.Image, cfg Config) Frame {
	grid := ToGrayscale(img, cfg.Width, cfg.Height)
	ascii := grid.ToASCII(cfg.Charset, cfg.Invert)
	return Frame{
		Grid:  ascii,
		Delay: cfg.autoDelay(),
		Info:  FrameInfo{Index: 0},
	}
}

// ─── Helpers ─────────────────────────────────────────────────────────────

// lerp linear interpolation.
func lerp(a, b, t float64) float64 { return a + (b-a)*t }

// clampInt clamps v to [lo, hi].
func clampInt(v, lo, hi int) int {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

// normalizeClamp clamps v to [0, 1].
func normalizeClamp(v float64) float64 {
	if v < 0 {
		return 0
	}
	if v > 1 {
		return 1
	}
	return v
}

// PadGrid pads all rows to the same length (in case of variable width).
func PadGrid(rows []string) []string {
	if len(rows) == 0 {
		return rows
	}
	maxW := 0
	for _, r := range rows {
		if len(r) > maxW {
			maxW = len(r)
		}
	}
	out := make([]string, len(rows))
	for i, r := range rows {
		if len(r) < maxW {
			out[i] = r + strings.Repeat(" ", maxW-len(r))
		} else {
			out[i] = r
		}
	}
	return out
}
