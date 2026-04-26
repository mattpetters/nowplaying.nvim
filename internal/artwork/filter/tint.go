package filter

import (
	"image"
	"image/color"
)

// Tint multiplies an image's per-pixel luminance by an RGB color. The
// result reads as a monochrome wash in the tint color — green for matrix,
// amber for CRT, etc. Works best on a desaturated input.
type Tint struct {
	R, G, B uint8 // tint target in 8-bit sRGB
}

// HexTint parses a "#rrggbb" string. Returns black on parse error so
// the pipeline never panics on bad config.
func HexTint(hex string) Tint {
	r, g, b := parseHex(hex)
	return Tint{R: r, G: g, B: b}
}

func (t Tint) Apply(src image.Image) image.Image {
	b := src.Bounds()
	dst := image.NewRGBA(b)
	tr, tg, tb := float64(t.R)/255.0, float64(t.G)/255.0, float64(t.B)/255.0
	for y := b.Min.Y; y < b.Max.Y; y++ {
		for x := b.Min.X; x < b.Max.X; x++ {
			r, g, bl, a := src.At(x, y).RGBA()
			// Use luminance of the source pixel (Rec. 709) as the scalar.
			lum := (0.2126*float64(r) + 0.7152*float64(g) + 0.0722*float64(bl)) / 0xffff
			c := color.RGBA{
				R: uint8(clamp(lum*tr) * 255),
				G: uint8(clamp(lum*tg) * 255),
				B: uint8(clamp(lum*tb) * 255),
				A: uint8(a >> 8),
			}
			dst.SetRGBA(x, y, c)
		}
	}
	return dst
}

func clamp(v float64) float64 {
	if v < 0 {
		return 0
	}
	if v > 1 {
		return 1
	}
	return v
}

// parseHex accepts "#rrggbb" or "rrggbb". Bad input → 0,0,0.
func parseHex(s string) (uint8, uint8, uint8) {
	if len(s) > 0 && s[0] == '#' {
		s = s[1:]
	}
	if len(s) != 6 {
		return 0, 0, 0
	}
	var r, g, b uint8
	for i, c := range s {
		var v uint8
		switch {
		case c >= '0' && c <= '9':
			v = uint8(c - '0')
		case c >= 'a' && c <= 'f':
			v = uint8(c-'a') + 10
		case c >= 'A' && c <= 'F':
			v = uint8(c-'A') + 10
		default:
			return 0, 0, 0
		}
		switch i {
		case 0:
			r = v << 4
		case 1:
			r |= v
		case 2:
			g = v << 4
		case 3:
			g |= v
		case 4:
			b = v << 4
		case 5:
			b |= v
		}
	}
	return r, g, b
}
