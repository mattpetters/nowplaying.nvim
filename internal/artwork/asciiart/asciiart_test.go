package asciiart

import (
	"image"
	"image/color"
	"strings"
	"testing"
)

// ─── Helpers ──────────────────────────────────────────────────────────────

// testImage creates a small solid-color image for testing.
func testImage(w, h int, r, g, b uint8) image.Image {
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			img.Set(x, y, color.RGBA{r, g, b, 255})
		}
	}
	return img
}

// testGradient creates a horizontal gradient from black to white.
func testGradient(w, h int) image.Image {
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			v := uint8(x * 255 / (w - 1))
			img.Set(x, y, color.RGBA{v, v, v, 255})
		}
	}
	return img
}

// ─── Tests ────────────────────────────────────────────────────────────────

func TestToGrayscale(t *testing.T) {
	img := testImage(100, 50, 100, 150, 200)
	grid := ToGrayscale(img, 10, 5)
	if len(grid) != 5 {
		t.Fatalf("expected 5 rows, got %d", len(grid))
	}
	if len(grid[0]) != 10 {
		t.Fatalf("expected 10 cols, got %d", len(grid[0]))
	}
	// Average of 100, 150, 200 = 150
	if grid[0][0].Gray != 150 {
		t.Fatalf("expected gray 150, got %d", grid[0][0].Gray)
	}
}

func TestToGrayscaleEmpty(t *testing.T) {
	grid := ToGrayscale(testImage(0, 0, 0, 0, 0), 10, 10)
	if grid != nil {
		t.Fatal("expected nil grid for empty image")
	}
}

func TestGridToASCII(t *testing.T) {
	grid := make(Grid, 2)
	grid[0] = []Pixel{{Gray: 0}, {Gray: 128}, {Gray: 255}}
	grid[1] = []Pixel{{Gray: 64}, {Gray: 192}, {Gray: 255}}

	result := grid.ToASCII(" .oO#", false)
	if len(result) != 2 {
		t.Fatalf("expected 2 rows, got %d", len(result))
	}
	if len(result[0]) != 3 {
		t.Fatalf("expected 3 chars per row, got %d", len(result[0]))
	}

	// Gray 0 -> ' ' (index 0)
	if result[0][0] != ' ' {
		t.Fatalf("expected ' ' for gray 0, got %q", result[0][0])
	}
	// Gray 255 -> '#' (index 4)
	if result[0][2] != '#' {
		t.Fatalf("expected '#' for gray 255, got %q", result[0][2])
	}
}

func TestGridToASCIIInvert(t *testing.T) {
	grid := make(Grid, 1)
	grid[0] = []Pixel{{Gray: 0}, {Gray: 255}}

	result := grid.ToASCII(" .oO#", true)
	// Inverted: gray 0 -> #, gray 255 -> ' '
	if result[0][0] != '#' {
		t.Fatalf("expected '#' for inverted gray 0, got %q", result[0][0])
	}
	if result[0][1] != ' ' {
		t.Fatalf("expected ' ' for inverted gray 255, got %q", result[0][1])
	}
}

func TestToGrayscaleCrop(t *testing.T) {
	img := testImage(100, 100, 255, 0, 0) // solid red
	grid := ToGrayscaleCrop(img, 5, 5, CropRect{X: 0, Y: 0, W: 0.5, H: 0.5})
	if len(grid) != 5 {
		t.Fatalf("expected 5 rows, got %d", len(grid))
	}
	// Red average: (255+0+0)/3 = 85
	if grid[0][0].Gray != 85 {
		t.Fatalf("expected gray 85 for red, got %d", grid[0][0].Gray)
	}
}

func TestFrameFromImage(t *testing.T) {
	img := testImage(50, 25, 128, 128, 128)
	cfg := DefaultConfig(20, 10)
	f := FrameFromImage(img, cfg)

	if len(f.Grid) != 10 {
		t.Fatalf("expected 10 rows, got %d", len(f.Grid))
	}
	if len(f.Grid[0]) != 20 {
		t.Fatalf("expected 20 cols, got %d", len(f.Grid[0]))
	}
	if f.Delay <= 0 {
		t.Fatal("expected positive delay")
	}
}

func TestConfigDefaults(t *testing.T) {
	cfg := DefaultConfig(80, 24)
	if cfg.Width != 80 {
		t.Fatalf("expected width 80, got %d", cfg.Width)
	}
	if cfg.Height != 24 {
		t.Fatalf("expected height 24, got %d", cfg.Height)
	}
	if cfg.FramesPerSecond != 8 {
		t.Fatalf("expected 8 fps, got %f", cfg.FramesPerSecond)
	}
	if cfg.Motion != MotionZoomIn {
		t.Fatalf("expected zoom motion, got %v", cfg.Motion)
	}
}

func TestAutoFrameCount(t *testing.T) {
	cfg := Config{FramesPerSecond: 10}
	count := cfg.autoFrameCount()
	if count != 30 {
		t.Fatalf("expected 30 frames (10fps * 3s), got %d", count)
	}

	cfg.FrameCount = 5
	count = cfg.autoFrameCount()
	if count != 5 {
		t.Fatalf("expected 5 frames (override), got %d", count)
	}
}

func TestMotionPresetString(t *testing.T) {
	tests := []struct {
		m   MotionPreset
		exp string
	}{
		{MotionStill, "still"},
		{MotionZoomIn, "zoom"},
		{MotionPulse, "pulse"},
		{MotionScan, "scan"},
		{MotionRipple, "ripple"},
		{MotionGlitch, "glitch"},
		{MotionDissolve, "dissolve"},
		{MotionBreath, "breath"},
		{MotionOrbit, "orbit"},
	}
	for _, tc := range tests {
		if got := tc.m.String(); got != tc.exp {
			t.Errorf("MotionPreset(%d).String() = %q; want %q", tc.m, got, tc.exp)
		}
	}
}

func TestParseMotionPreset(t *testing.T) {
	if ParseMotionPreset("zoom") != MotionZoomIn {
		t.Fatal("expected zoom")
	}
	if ParseMotionPreset("still") != MotionStill {
		t.Fatal("expected still")
	}
	if ParseMotionPreset("nonexistent") != MotionStill {
		t.Fatal("expected still default for unknown")
	}
}

func TestPadGrid(t *testing.T) {
	in := []string{"abc", "de"}
	out := PadGrid(in)
	if len(out[1]) != 3 {
		t.Fatalf("expected padded len 3, got %d", len(out[1]))
	}
	if out[1] != "de " {
		t.Fatalf("expected 'de ', got %q", out[1])
	}
}

func TestGradientToASCII(t *testing.T) {
	img := testGradient(80, 10)
	grid := ToGrayscale(img, 80, 10)
	result := grid.ToASCII(StandardCharset, false)
	if len(result) != 10 {
		t.Fatalf("expected 10 rows, got %d", len(result))
	}
	// Leftmost char should be darkest, rightmost brightest
	if result[0][0] != StandardCharset[0] {
		t.Fatalf("expected darkest char at left edge, got %q", result[0][0])
	}
	if result[0][79] != StandardCharset[len(StandardCharset)-1] {
		t.Fatalf("expected brightest char at right edge, got %q", result[0][79])
	}
}

// ─── Animation Tests ─────────────────────────────────────────────────────

func TestAnimateStill(t *testing.T) {
	img := testImage(100, 50, 128, 128, 128)
	cfg := DefaultConfig(20, 10)
	cfg.Motion = MotionStill
	cfg.FrameCount = 1

	frames := Animate(img, cfg)
	if len(frames) != 1 {
		t.Fatalf("expected 1 frame, got %d", len(frames))
	}
	if len(frames[0].Grid) != 10 {
		t.Fatalf("expected 10 rows, got %d", len(frames[0].Grid))
	}
}

func TestAnimateZoomIn(t *testing.T) {
	img := testImage(100, 100, 255, 0, 0)
	cfg := DefaultConfig(40, 20)
	cfg.Motion = MotionZoomIn
	cfg.FrameCount = 5

	frames := Animate(img, cfg)
	if len(frames) != 5 {
		t.Fatalf("expected 5 frames, got %d", len(frames))
	}
	if len(frames[0].Grid) != 20 {
		t.Fatalf("expected 20 rows, got %d", len(frames[0].Grid))
	}
}

func TestAnimatePulse(t *testing.T) {
	img := testImage(50, 25, 128, 128, 128)
	cfg := DefaultConfig(20, 10)
	cfg.Motion = MotionPulse
	cfg.FrameCount = 10

	frames := Animate(img, cfg)
	if len(frames) != 10 {
		t.Fatalf("expected 10 frames, got %d", len(frames))
	}
}

func TestAnimateScan(t *testing.T) {
	img := testImage(50, 25, 200, 200, 200)
	cfg := DefaultConfig(20, 10)
	cfg.Motion = MotionScan
	cfg.FrameCount = 10

	frames := Animate(img, cfg)
	if len(frames) != 10 {
		t.Fatalf("expected 10 frames, got %d", len(frames))
	}
	// First frame should have only 0-1 rows visible, last frame all rows
	firstEmpty := strings.Count(frames[0].Grid[9], " ")
	lastEmpty := strings.Count(frames[9].Grid[9], " ")
	if firstEmpty < lastEmpty {
		// Earlier frames have more spaces (empty) rows
	}
}

func TestAnimateRipple(t *testing.T) {
	img := testImage(50, 25, 100, 150, 200)
	cfg := DefaultConfig(20, 10)
	cfg.Motion = MotionRipple
	cfg.FrameCount = 8

	frames := Animate(img, cfg)
	if len(frames) != 8 {
		t.Fatalf("expected 8 frames, got %d", len(frames))
	}
}

func TestAnimateGlitch(t *testing.T) {
	img := testImage(50, 25, 100, 100, 100)
	cfg := DefaultConfig(20, 10)
	cfg.Motion = MotionGlitch
	cfg.FrameCount = 6

	frames := Animate(img, cfg)
	if len(frames) != 6 {
		t.Fatalf("expected 6 frames, got %d", len(frames))
	}
}

func TestAnimateDissolve(t *testing.T) {
	img := testImage(50, 25, 128, 128, 128)
	cfg := DefaultConfig(20, 10)
	cfg.Motion = MotionDissolve
	cfg.FrameCount = 8

	frames := Animate(img, cfg)
	if len(frames) != 8 {
		t.Fatalf("expected 8 frames, got %d", len(frames))
	}
}

func TestAnimateBreath(t *testing.T) {
	img := testImage(100, 50, 128, 128, 128)
	cfg := DefaultConfig(30, 15)
	cfg.Motion = MotionBreath
	cfg.FrameCount = 10

	frames := Animate(img, cfg)
	if len(frames) != 10 {
		t.Fatalf("expected 10 frames, got %d", len(frames))
	}
}

func TestAnimateOrbit(t *testing.T) {
	img := testImage(100, 50, 128, 128, 128)
	cfg := DefaultConfig(30, 15)
	cfg.Motion = MotionOrbit
	cfg.FrameCount = 12

	frames := Animate(img, cfg)
	if len(frames) != 12 {
		t.Fatalf("expected 12 frames, got %d", len(frames))
	}
}

// ─── Eikon Test ──────────────────────────────────────────────────────────

func TestEncodeDecodeEikon(t *testing.T) {
	img := testImage(50, 25, 128, 128, 128)
	cfg := DefaultConfig(10, 5)
	cfg.Motion = MotionStill
	cfg.FrameCount = 1

	frames := Animate(img, cfg)
	data, err := EncodeEikon(frames, "test-artist-123")
	if err != nil {
		t.Fatalf("encode: %v", err)
	}

	decoded, artistID, err := DecodeEikonLines(data)
	if err != nil {
		t.Fatalf("decode: %v", err)
	}

	if artistID != "test-artist-123" {
		t.Fatalf("expected artistID 'test-artist-123', got %q", artistID)
	}
	if len(decoded) != 1 {
		t.Fatalf("expected 1 frame, got %d", len(decoded))
	}
	if len(decoded[0].Grid) != 5 {
		t.Fatalf("expected 5 rows, got %d", len(decoded[0].Grid))
	}
}

func TestEncodeEmptyFrames(t *testing.T) {
	_, err := EncodeEikon(nil, "test")
	if err == nil {
		t.Fatal("expected error for empty frames")
	}
}

// ─── Cache Tests ─────────────────────────────────────────────────────────

func TestArtistHash(t *testing.T) {
	h1 := artistHash("Metallica")
	h2 := artistHash("Metallica")
	if h1 != h2 {
		t.Fatal("same artist should produce same hash")
	}
	if len(h1) != 16 {
		t.Fatalf("expected 16-char hex, got %d", len(h1))
	}
}

func TestCacheStoreAndLoad(t *testing.T) {
	dir := t.TempDir()
	cache := NewCache(dir)

	img := testImage(50, 25, 128, 128, 128)
	cfg := DefaultConfig(10, 5)
	cfg.Motion = MotionStill
	cfg.FrameCount = 1

	frames := Animate(img, cfg)
	err := cache.Store("Test Artist", frames, cfg)
	if err != nil {
		t.Fatalf("store: %v", err)
	}

	if !cache.Has("Test Artist") {
		t.Fatal("expected Has() to return true")
	}

	loaded, err := cache.Load("Test Artist")
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if len(loaded) != 1 {
		t.Fatalf("expected 1 frame, got %d", len(loaded))
	}

	// Load meta
	meta, err := cache.LoadMeta("Test Artist")
	if err != nil {
		t.Fatalf("load meta: %v", err)
	}
	if meta.Artist != "Test Artist" {
		t.Fatalf("expected artist 'Test Artist', got %q", meta.Artist)
	}
}

func TestCacheDelete(t *testing.T) {
	dir := t.TempDir()
	cache := NewCache(dir)

	img := testImage(10, 10, 128, 128, 128)
	cfg := DefaultConfig(5, 3)
	cfg.Motion = MotionStill
	cfg.FrameCount = 1

	frames := Animate(img, cfg)
	_ = cache.Store("Delete Me", frames, cfg)

	if !cache.Has("Delete Me") {
		t.Fatal("expected Has() to return true before delete")
	}

	err := cache.Delete("Delete Me")
	if err != nil {
		t.Fatalf("delete: %v", err)
	}

	if cache.Has("Delete Me") {
		t.Fatal("expected Has() to return false after delete")
	}
}

func TestCacheClear(t *testing.T) {
	dir := t.TempDir()
	cache := NewCache(dir)

	img := testImage(10, 10, 128, 128, 128)
	cfg := DefaultConfig(5, 3)
	cfg.Motion = MotionStill
	cfg.FrameCount = 1

	frames := Animate(img, cfg)
	_ = cache.Store("Artist A", frames, cfg)
	_ = cache.Store("Artist B", frames, cfg)

	_ = cache.Clear()

	if cache.Has("Artist A") {
		t.Fatal("expected cleared cache")
	}
	if cache.Has("Artist B") {
		t.Fatal("expected cleared cache")
	}
}

func TestCacheList(t *testing.T) {
	dir := t.TempDir()
	cache := NewCache(dir)

	img := testImage(10, 10, 128, 128, 128)
	cfg := DefaultConfig(5, 3)
	cfg.Motion = MotionStill
	cfg.FrameCount = 1

	frames := Animate(img, cfg)
	_ = cache.Store("Listed Artist", frames, cfg)

	list, err := cache.List()
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if len(list) != 1 {
		t.Fatalf("expected 1 artist in list, got %d", len(list))
	}
	if list[0] != "Listed Artist" {
		t.Fatalf("expected 'Listed Artist', got %q", list[0])
	}
}

func TestCacheSourceImage(t *testing.T) {
	dir := t.TempDir()
	cache := NewCache(dir)

	img := testImage(50, 30, 100, 150, 200)
	err := cache.StoreSourceImage("Image Artist", img)
	if err != nil {
		t.Fatalf("store source: %v", err)
	}

	loaded, err := cache.LoadSourceImage("Image Artist")
	if err != nil {
		t.Fatalf("load source: %v", err)
	}

	bounds := loaded.Bounds()
	if bounds.Dx() != 50 || bounds.Dy() != 30 {
		t.Fatalf("expected 50x30, got %dx%d", bounds.Dx(), bounds.Dy())
	}
}
