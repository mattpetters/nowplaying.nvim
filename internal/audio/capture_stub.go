//go:build !(darwin && cgo)

package audio

func captureAvailable() bool { return false }

func captureStart(_ string) error { return ErrNotSupported }

func captureStop() {}

func captureRead(_ []float32) int { return 0 }
