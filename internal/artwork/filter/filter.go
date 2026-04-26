// Package filter provides a composable image-processing pipeline used to
// stylize album art under a theme. Filters consume and produce
// image.Image; the pipeline runs once per track change in the TUI.
package filter

import "image"

// Filter mutates an image. Filters must be deterministic — golden-image
// tests rely on it.
type Filter interface {
	Apply(image.Image) image.Image
}

// Pipeline is an ordered sequence of filters.
type Pipeline []Filter

// Apply runs every filter in order. An empty pipeline returns the input
// unchanged.
func (p Pipeline) Apply(img image.Image) image.Image {
	out := img
	for _, f := range p {
		out = f.Apply(out)
	}
	return out
}

// FilterFunc adapts an ordinary function to the Filter interface.
type FilterFunc func(image.Image) image.Image

func (f FilterFunc) Apply(img image.Image) image.Image { return f(img) }
