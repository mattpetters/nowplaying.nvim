# Handoff: Real Audio Spectrum Visualizer

**Branch:** `feat/standalone-tui`
**Date:** 2026-05-12
**Status:** Ready for implementation

## Context

The standalone TUI (`cmd/nowplaying/tui`) has a braille-character spectrum
visualizer that fakes beats with sine waves and a simulated drum pattern.
It looks OK but doesn't react to actual music. This spec covers wiring
real audio FFT data from the system into the visualizer.

### What exists today

- **Daemon** (`cmd/nowplayingd`) — Go, serves JSON-RPC over Unix socket.
  Providers implement `internal/providers.Provider` and publish
  `state.Observation` to `internal/state.Machine`. The machine fans out
  notifications to all subscribed clients.
- **Spotify provider** (`internal/providers/spotify`) — polls Spotify via
  osascript at 1Hz. Gives us track metadata, position, volume — no audio.
- **TUI visualizer** (`cmd/nowplaying/tui/visualizer.go`) — stateful
  per-bar heights with attack/decay physics. `tickPlaying()` drives bars
  from `beatEnergy()` (fake). `tickPaused()` applies gravity decay.
  Currently has `vizEqualizer`, `vizWave`, `vizHelix` modes.
- **Existing notifications** in `internal/proto/proto.go`:
  `state.changed`, `track.changed`, `progress.tick`, `auth.required`, `error`.

### What we want

The daemon captures Spotify's audio output via ScreenCaptureKit, runs an
FFT, and streams frequency band levels to connected clients. The TUI
visualizer drives its bars from real spectrum data instead of the fake
beat simulation. When no audio data is available, it falls back to the
current simulated mode.

---

## Architecture

```
┌──────────────────────────────────────────────┐
│  nowplayingd                                 │
│                                              │
│  ┌──────────────────────┐                    │
│  │ audio/capture.go     │ ← cgo / Swift      │
│  │ ScreenCaptureKit     │   helper            │
│  │ tap Spotify process  │                    │
│  └──────────┬───────────┘                    │
│             │ raw PCM samples                │
│  ┌──────────▼───────────┐                    │
│  │ audio/fft.go         │                    │
│  │ 1024-sample FFT      │                    │
│  │ → N band magnitudes  │                    │
│  └──────────┬───────────┘                    │
│             │ []float64 band levels          │
│  ┌──────────▼───────────┐                    │
│  │ state machine        │                    │
│  │ audio.spectrum notif │                    │
│  └──────────┬───────────┘                    │
└─────────────┼────────────────────────────────┘
              │ JSON-RPC notification
         ┌────▼─────┐
         │ TUI      │
         │ viz.feed()│
         └──────────┘
```

---

## Implementation Plan

### Phase 1: Audio capture helper (Swift/ObjC → C bridge)

**File:** `internal/audio/capture_darwin.go` + `internal/audio/capture_darwin.m` (or `.swift`)

Use `SCContentSharingPicker` / `SCShareableContent` (ScreenCaptureKit,
macOS 13+) to:

1. Find the Spotify process by bundle ID (`com.spotify.client`).
2. Create an `SCContentFilter` scoped to that application.
3. Create an `SCStreamConfiguration` with audio-only capture:
   - `capturesAudio = true`, `excludesCurrentProcessAudio = true`
   - `channelCount = 1` (mono is fine for spectrum)
   - `sampleRate = 44100`
4. Start an `SCStream` and install an `SCStreamOutput` delegate.
5. On each `stream(_:didOutputSampleBuffer:of:)` callback with
   `.audio` type, extract the `CMSampleBuffer` → `AudioBufferList`
   → float32 PCM samples.
6. Write samples into a lock-free ring buffer shared with the Go side.

**cgo bridge:** expose two C functions:
```c
int  audio_capture_start(const char *bundle_id);  // returns 0 on success
void audio_capture_stop(void);
int  audio_capture_read(float *buf, int max_samples);  // returns num read
```

Go calls these from `internal/audio/capture_darwin.go` via cgo.

**Build tag:** `//go:build darwin` — the feature is macOS-only. Provide a
`capture_stub.go` with `//go:build !darwin` that returns
`errNotSupported` so the project still compiles on Linux/CI.

**Permissions:** ScreenCaptureKit requires the "Screen & System Audio
Recording" permission. The first call triggers a system prompt. The
daemon should handle the `SCStreamErrorUserDeclined` case gracefully and
fall back to simulated mode.

### Phase 2: FFT and band extraction

**File:** `internal/audio/fft.go`

Pure Go FFT (use `github.com/mjibson/go-dsp/fft` or write a radix-2
Cooley-Tukey — the sample count is always a power of 2).

1. Consume samples from the ring buffer in 1024-sample windows
   (overlapping 50% is nice but not required for v1).
2. Apply a Hann window.
3. Run complex FFT → take magnitudes of the first N/2 bins.
4. Group bins into `N` bands (N = 16 or 32, configurable). Use
   logarithmic bin grouping so bass bands cover fewer bins and treble
   bands cover more — matches human perception.
5. Convert magnitudes to dB scale, normalize to 0.0–1.0 range.
6. Output: `[]float64` of length N, values in [0, 1].

Target update rate: ~30 Hz (every ~33ms). This means processing
~1,470 samples per update at 44.1 kHz, so a 1024 + 512 overlap window
works well.

### Phase 3: Wire into daemon notifications

**Files:** `internal/proto/proto.go`, `internal/daemon/daemon.go`

Add a new notification:
```go
// proto.go
NotifyAudioSpectrum = "audio.spectrum"

type AudioSpectrum struct {
    Bands []float64 `json:"bands"` // normalized 0.0–1.0
}
```

In the daemon, start the audio capture goroutine alongside providers.
On each FFT output, publish `audio.spectrum` through the state machine's
event bus (or directly via `server.Broadcast` — spectrum data doesn't
need state machine dedup since it's ephemeral).

When audio capture is unavailable (permission denied, not macOS, Spotify
not running), the daemon simply never emits `audio.spectrum`. Clients
must handle its absence.

### Phase 4: TUI visualizer consumes real data

**File:** `cmd/nowplaying/tui/visualizer.go`, `cmd/nowplaying/tui/model.go`

Add to visualizer:
```go
func (v *visualizer) feed(bands []float64) {
    v.realBands = bands
    v.hasRealData = true
    v.lastFeed = time.Now()
}
```

In `tickPlaying()`:
- If `v.hasRealData` and `lastFeed` is fresh (< 200ms): drive bar
  targets from `realBands` instead of `beatEnergy()`. Map each band's
  0.0–1.0 value to `maxHeight`. The existing attack/decay/peak-hold
  physics still apply — just the *target* source changes.
- If data goes stale (> 200ms without a feed): fall back to simulated
  beat mode. Log once so the user knows.

In `model.go`, handle the new notification:
```go
case notifMsg:
    if msg.msg.Method == proto.NotifyAudioSpectrum {
        var s proto.AudioSpectrum
        json.Unmarshal(msg.msg.Params, &s)
        m.viz.feed(s.Bands)
    }
    // ... existing applyNotification
```

The number of bands from the daemon may not match `v.bars`. Resample
with linear interpolation in `feed()`.

### Phase 5: Graceful degradation

Hierarchy of visualizer modes (automatic, not user-toggled):
1. **Real spectrum** — `audio.spectrum` notifications arriving.
2. **Simulated beats** — playing but no audio data.
3. **Gravity decay** — paused.
4. **Flat** — stopped / no track.

Transitions should be seamless — the attack/decay physics smooth over
any data source change.

---

## Key Files to Touch

| File | Change |
|------|--------|
| `internal/audio/capture_darwin.go` | NEW — cgo bridge to ScreenCaptureKit |
| `internal/audio/capture_darwin.m` | NEW — ObjC/Swift audio capture impl |
| `internal/audio/capture_stub.go` | NEW — no-op for non-darwin builds |
| `internal/audio/fft.go` | NEW — FFT + band extraction |
| `internal/audio/fft_test.go` | NEW — test with known waveforms |
| `internal/proto/proto.go` | Add `NotifyAudioSpectrum`, `AudioSpectrum` type |
| `internal/daemon/daemon.go` | Start audio capture goroutine, broadcast spectrum |
| `cmd/nowplaying/tui/visualizer.go` | Add `feed()`, real-data path in `tickPlaying()` |
| `cmd/nowplaying/tui/model.go` | Handle `audio.spectrum` notification |
| `go.mod` | Add FFT dependency if using external lib |

## Testing

- **FFT:** feed a known sine wave (e.g., 440 Hz), assert the
  corresponding bin has the dominant magnitude.
- **Band grouping:** feed white noise, assert all bands are
  approximately equal.
- **Visualizer feed:** call `feed()` with known band data, call
  `tickPlaying()`, assert heights converge toward the fed values.
- **Fallback:** assert that `tickPlaying()` uses simulated beats when
  `hasRealData` is false.
- **Build tags:** CI runs `go build ./...` on Linux — must compile
  with the stub.

## Dependencies

- `github.com/mjibson/go-dsp` (optional — can hand-roll radix-2 FFT)
- macOS 13+ for ScreenCaptureKit
- cgo enabled for darwin builds

## Open Questions

1. **ScreenCaptureKit vs AudioToolbox tap:** SCK is the modern API and
   can target a specific app. AudioToolbox aggregate devices capture all
   system audio but require a virtual device (BlackHole). SCK is the
   right call unless we hit permission UX issues.
2. **Band count:** 16 bands is enough for a braille visualizer that
   maxes at ~32 bars. Ship 16, let the TUI interpolate.
3. **Latency budget:** SCK adds ~20-50ms. FFT adds ~23ms (1024 samples
   at 44.1 kHz). Total ~50-70ms visual latency is fine for a TUI.
4. **Battery impact:** mono 44.1 kHz capture + 30 Hz FFT is negligible.
   Bigger concern is the TUI re-rendering at 30 Hz — but it already
   ticks at 10 Hz (100ms), so we may want to bump the tick or decouple
   viz rendering from the main tick.

---

## Session Summary (what was done today)

1. **Spotify osascript provider** (`internal/providers/spotify/`) — real
   playback control via AppleScript. Daemon auto-detects Spotify and
   falls back to stub.
2. **Braille visualizer** (`cmd/nowplaying/tui/visualizer.go`) — ported
   `gridToBraille` from unicode-animations. 3 modes: equalizer (2-row
   tall, beat-driven spike/decay with peak hold), wave, helix. Gravity
   trickle-down on pause.
3. **`v` key** cycles visualizer mode, hint bar updated.
4. All tests passing, goldens regenerated.
