package filter

import (
	"image"
	"image/color"
)

// bayer4x4 is the standard 4×4 ordered-dither threshold matrix,
// normalized into [0, 1) by dividing by 16.
var bayer4x4 = [4][4]float64{
	{0, 8, 2, 10},
	{12, 4, 14, 6},
	{3, 11, 1, 9},
	{15, 7, 13, 5},
}

// Dither applies an ordered (Bayer 4×4) dither and quantizes each
// channel to Levels distinct values. Levels=2 gives pure black/white,
// 4 gives the classic chunky CRT look.
type Dither struct {
	Levels int // >=2; values <2 are treated as 2
}

func (d Dither) Apply(src image.Image) image.Image {
	levels := max(d.Levels, 2)
	step := 255 / float64(levels-1)
	b := src.Bounds()
	dst := image.NewRGBA(b)
	for y := b.Min.Y; y < b.Max.Y; y++ {
		for x := b.Min.X; x < b.Max.X; x++ {
			r, g, bl, a := src.At(x, y).RGBA()
			// Per-pixel threshold offset, normalized then scaled to step size.
			t := (bayer4x4[(y-b.Min.Y)&3][(x-b.Min.X)&3]/16 - 0.5) * step
			r8 := quantize(float64(r>>8)+t, step, levels)
			g8 := quantize(float64(g>>8)+t, step, levels)
			b8 := quantize(float64(bl>>8)+t, step, levels)
			dst.SetRGBA(x, y, color.RGBA{R: r8, G: g8, B: b8, A: uint8(a >> 8)})
		}
	}
	return dst
}

func quantize(v, step float64, levels int) uint8 {
	idx := int((v + step/2) / step)
	idx = max(idx, 0)
	idx = min(idx, levels-1)
	return uint8(float64(idx) * step)
}
