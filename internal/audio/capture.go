package audio

import "errors"

var ErrNotSupported = errors.New("audio capture not supported on this platform")

// Capture manages system audio capture. On macOS, it uses ScreenCaptureKit
// to tap a specific application's audio output.
type Capture struct{}

// Available reports whether audio capture is available on this platform.
func (c *Capture) Available() bool {
	return captureAvailable()
}

// Start begins capturing audio from the application with the given bundle ID.
func (c *Capture) Start(bundleID string) error {
	return captureStart(bundleID)
}

// Stop stops audio capture.
func (c *Capture) Stop() {
	captureStop()
}

// Read reads captured PCM samples into buf and returns the number read.
func (c *Capture) Read(buf []float32) int {
	return captureRead(buf)
}
