package filter

import (
	"image"
	"image/color"
)

// Desaturate converts an image to grayscale using Rec. 709 luminance.
type Desaturate struct{}

func (Desaturate) Apply(src image.Image) image.Image {
	b := src.Bounds()
	dst := image.NewRGBA(b)
	for y := b.Min.Y; y < b.Max.Y; y++ {
		for x := b.Min.X; x < b.Max.X; x++ {
			r, g, bl, a := src.At(x, y).RGBA()
			// RGBA returns 16-bit values. Rec. 709 weights.
			y16 := min(uint32(0.2126*float64(r)+0.7152*float64(g)+0.0722*float64(bl)), 0xffff)
			c := color.RGBA{
				R: uint8(y16 >> 8),
				G: uint8(y16 >> 8),
				B: uint8(y16 >> 8),
				A: uint8(a >> 8),
			}
			dst.SetRGBA(x, y, c)
		}
	}
	return dst
}
