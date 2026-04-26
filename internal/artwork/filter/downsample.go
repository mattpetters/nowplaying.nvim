package filter

import "image"

// Downsample shrinks an image to (Size × Size) using nearest-neighbor
// sampling. The terminal upscales the result back to its display
// rectangle, producing visible square pixels — the lo-fi look.
type Downsample struct {
	Size int // pixels along each side after downsampling; <=0 disables
}

func (d Downsample) Apply(src image.Image) image.Image {
	if d.Size <= 0 {
		return src
	}
	sb := src.Bounds()
	dw, dh := d.Size, d.Size
	dst := image.NewRGBA(image.Rect(0, 0, dw, dh))
	xRatio := float64(sb.Dx()) / float64(dw)
	yRatio := float64(sb.Dy()) / float64(dh)
	for y := range dh {
		sy := sb.Min.Y + int(float64(y)*yRatio)
		for x := range dw {
			sx := sb.Min.X + int(float64(x)*xRatio)
			dst.Set(x, y, src.At(sx, sy))
		}
	}
	return dst
}
