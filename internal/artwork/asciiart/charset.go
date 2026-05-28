package asciiart

// Standard charset definitions for ASCII art conversion.
// Each string goes from darkest character (index 0) to brightest.
//
// You can supply any string of characters sorted by visual weight;
// the converter maps grayscale 0-255 linearly to the set.

const (
	// StandardCharset is a classic 10-character ramp.
	StandardCharset = " .:-=+*#%%@"

	// DenseCharset gives smoother gradients with more steps.
	DenseCharset = " .'`^\",:;Il!i><~+_-?][}{1)(|\\/tfjrxnuvczXYUJCLQ0OZmwqpdbkhao*#MW&8%%B@$"

	// BlockCharset uses unicode block characters for solid fills.
	BlockCharset = " \\xe2\\x96\\x81\\xe2\\x96\\x82\\xe2\\x96\\x83\\xe2\\x96\\x84\\xe2\\x96\\x85\\xe2\\x96\\x86\\xe2\\x96\\x87\\xe2\\x96\\x88"

	// MinimalCharset is a short 4-character ramp for high contrast.
	MinimalCharset = " .#@"

	// StrokeCharset emulates pen/ink strokes with varying line weights.
	StrokeCharset = " `-:'|/\\\\_=+*#%@"

	// InvertedCharset is the standard set reversed (bright -> dark).
	InvertedCharset = "@%%#*+=-:. "
)
