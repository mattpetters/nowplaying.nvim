//go:build darwin && cgo

package audio

/*
#cgo LDFLAGS: -framework ScreenCaptureKit -framework CoreMedia -framework AudioToolbox -framework Foundation

#include <stdlib.h>

extern int  audio_capture_available(void);
extern int  audio_capture_start(const char *bundle_id);
extern void audio_capture_stop(void);
extern int  audio_capture_read(float *buf, int max_samples);
*/
import "C"
import "unsafe"

func captureAvailable() bool {
	return C.audio_capture_available() != 0
}

func captureStart(bundleID string) error {
	cbid := C.CString(bundleID)
	defer C.free(unsafe.Pointer(cbid))
	if C.audio_capture_start(cbid) != 0 {
		return ErrNotSupported
	}
	return nil
}

func captureStop() {
	C.audio_capture_stop()
}

func captureRead(buf []float32) int {
	if len(buf) == 0 {
		return 0
	}
	return int(C.audio_capture_read(
		(*C.float)(unsafe.Pointer(&buf[0])),
		C.int(len(buf)),
	))
}
