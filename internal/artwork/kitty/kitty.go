// Package kitty encodes images as kitty-graphics-protocol escape
// sequences. Ghostty implements this protocol natively.
//
// Reference: https://sw.kovidgoyal.net/kitty/graphics-protocol/
package kitty

import (
	"bytes"
	"encoding/base64"
	"fmt"
	"image"
	"image/png"
	"io"
)

// Options configures one transmission.
type Options struct {
	// ID is the image id (1..uint32 max). Reusing an id replaces the image.
	ID uint32
	// Cols/Rows place the image on the cell grid. Zero leaves the
	// default (terminal scales to image's pixel size).
	Cols int
	Rows int
	// PreserveAspect tells the terminal to letterbox.
	PreserveAspect bool
}

// Encode writes a kitty graphics transmission for img to w. The image is
// PNG-encoded then chunked into ≤4096-byte base64 frames.
func Encode(w io.Writer, img image.Image, opts Options) error {
	var pngBuf bytes.Buffer
	if err := png.Encode(&pngBuf, img); err != nil {
		return fmt.Errorf("encode png: %w", err)
	}
	encoded := base64.StdEncoding.EncodeToString(pngBuf.Bytes())

	const chunk = 4096
	first := true
	for len(encoded) > 0 {
		take := min(len(encoded), chunk)
		piece := encoded[:take]
		encoded = encoded[take:]
		more := 0
		if len(encoded) > 0 {
			more = 1
		}

		var keys string
		if first {
			keys = "a=T,f=100"
			if opts.ID != 0 {
				keys += fmt.Sprintf(",i=%d", opts.ID)
			}
			if opts.Cols > 0 {
				keys += fmt.Sprintf(",c=%d", opts.Cols)
			}
			if opts.Rows > 0 {
				keys += fmt.Sprintf(",r=%d", opts.Rows)
			}
			if opts.PreserveAspect {
				keys += ",z=0"
			}
			first = false
		}
		keys += fmt.Sprintf(",m=%d", more)

		// Trim leading comma if no other keys.
		if len(keys) > 0 && keys[0] == ',' {
			keys = keys[1:]
		}

		if _, err := fmt.Fprintf(w, "\x1b_G%s;%s\x1b\\", keys, piece); err != nil {
			return err
		}
	}
	return nil
}

// Delete removes a previously transmitted image with id from the screen.
// Useful before re-transmitting on track change.
func Delete(w io.Writer, id uint32) error {
	_, err := fmt.Fprintf(w, "\x1b_Ga=d,d=I,i=%d\x1b\\", id)
	return err
}
