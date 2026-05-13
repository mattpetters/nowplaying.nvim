package tui

import (
	"math"
	"testing"
)

func TestResampleBands_SameLength(t *testing.T) {
	src := []float64{0.1, 0.5, 0.9, 0.3}
	got := resampleBands(src, 4)
	for i, v := range got {
		if math.Abs(v-src[i]) > 1e-12 {
			t.Errorf("resampleBands[%d] = %g, want %g", i, v, src[i])
		}
	}
}

func TestResampleBands_Upsample(t *testing.T) {
	src := []float64{0.0, 1.0}
	got := resampleBands(src, 5)
	want := []float64{0.0, 0.25, 0.5, 0.75, 1.0}
	for i, v := range got {
		if math.Abs(v-want[i]) > 1e-12 {
			t.Errorf("resampleBands[%d] = %g, want %g", i, v, want[i])
		}
	}
}

func TestResampleBands_Downsample(t *testing.T) {
	src := []float64{0.0, 0.25, 0.5, 0.75, 1.0}
	got := resampleBands(src, 3)
	want := []float64{0.0, 0.5, 1.0}
	for i, v := range got {
		if math.Abs(v-want[i]) > 1e-12 {
			t.Errorf("resampleBands[%d] = %g, want %g", i, v, want[i])
		}
	}
}

func TestResampleBands_Empty(t *testing.T) {
	got := resampleBands(nil, 8)
	if len(got) != 8 {
		t.Fatalf("expected 8 bands, got %d", len(got))
	}
	for i, v := range got {
		if v != 0 {
			t.Errorf("band %d = %g, want 0", i, v)
		}
	}
}

func TestFeed_DrivesHeights(t *testing.T) {
	v := newVisualizer(8, 2)
	bands := []float64{1.0, 0.8, 0.6, 0.4, 0.2, 0.1, 0.05, 0.0}

	// Simulate continuous feed (as in real usage: ~30Hz feed vs 10Hz tick).
	for range 20 {
		v.feed(bands, nil)
		v.tick(true)
	}

	// Heights should converge toward band values * maxHeight.
	for i, b := range bands {
		target := b * maxHeight
		diff := math.Abs(v.heights[i] - target)
		if diff > 0.5 {
			t.Errorf("bar %d: height=%.2f, target=%.2f, diff=%.2f", i, v.heights[i], target, diff)
		}
	}
}

func TestFeed_Staleness(t *testing.T) {
	v := newVisualizer(8, 2)
	bands := make([]float64, 8)
	for i := range bands {
		bands[i] = 1.0
	}
	v.feed(bands, nil)

	if !v.feedFresh() {
		t.Error("feed should be fresh immediately after feeding")
	}

	// Tick past the stale threshold.
	for range feedStaleFrames + 1 {
		v.tick(true)
	}

	if v.feedFresh() {
		t.Errorf("feed should be stale after %d frames", feedStaleFrames+1)
	}
}

func TestFeed_FallbackToSimulated(t *testing.T) {
	v := newVisualizer(8, 2)

	// Start with continuous real data — all bars at max.
	bands := make([]float64, 8)
	for i := range bands {
		bands[i] = 1.0
	}
	for range 10 {
		v.feed(bands, nil)
		v.tick(true)
	}

	// Heights should be near maxHeight.
	for i, h := range v.heights {
		if h < maxHeight*0.5 {
			t.Errorf("with real data, bar %d height=%.2f, expected near %.2f", i, h, maxHeight)
		}
	}

	// Stop feeding — let it go stale and tick in "playing" mode.
	// Should switch to simulated beats rather than freezing.
	for range feedStaleFrames + 20 {
		v.tick(true)
	}

	anyNonZero := false
	for _, h := range v.heights {
		if h > 0.01 {
			anyNonZero = true
			break
		}
	}
	if !anyNonZero {
		t.Error("after stale feed, simulated mode should still produce non-zero heights")
	}
}
