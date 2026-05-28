package asciiart

import (
	"image"
	"math"
	"strings"
)

// Animate generates a sequence of frames from a single source image
// according to the configured motion preset.
func Animate(img image.Image, cfg Config) []Frame {
	count := cfg.autoFrameCount()
	if count <= 0 {
		count = 1
	}

	switch cfg.Motion {
	case MotionStill:
		return animateStill(img, cfg)
	case MotionZoomIn:
		return animateZoomIn(img, cfg, count)
	case MotionPulse:
		return animatePulse(img, cfg, count)
	case MotionScan:
		return animateScan(img, cfg, count)
	case MotionRipple:
		return animateRipple(img, cfg, count)
	case MotionGlitch:
		return animateGlitch(img, cfg, count)
	case MotionDissolve:
		return animateDissolve(img, cfg, count)
	case MotionBreath:
		return animateBreath(img, cfg, count)
	case MotionOrbit:
		return animateOrbit(img, cfg, count)
	default:
		return animateStill(img, cfg)
	}
}

// ─── Still ───────────────────────────────────────────────────────────────

func animateStill(img image.Image, cfg Config) []Frame {
	return []Frame{FrameFromImage(img, cfg)}
}

// ─── Zoom In (Ken Burns) ─────────────────────────────────────────────────

func animateZoomIn(img image.Image, cfg Config, n int) []Frame {
	frames := make([]Frame, n)
	delay := cfg.autoDelay()
	bounds := img.Bounds()
	srcW := float64(bounds.Dx())
	srcH := float64(bounds.Dy())

	fx, fy := cfg.FocalX, cfg.FocalY
	fx = normalizeClamp(fx)
	fy = normalizeClamp(fy)

	startScale := cfg.Scale
	endScale := cfg.Scale * 0.6

	for i := 0; i < n; i++ {
		t := float64(i) / float64(n-1)
		eased := easeInOutCubic(t)
		scale := lerp(startScale, endScale, eased)

		cropW := scale
		cropH := scale
		imgAspect := srcW / srcH
		cellAspect := float64(cfg.Width) / float64(cfg.Height)
		if imgAspect > cellAspect {
			cropH = cropW * cellAspect / imgAspect
		} else {
			cropW = cropH * imgAspect / cellAspect
		}

		crop := CropRect{
			X: fx - cropW/2,
			Y: fy - cropH/2,
			W: cropW,
			H: cropH,
		}

		grid := ToGrayscaleCrop(img, cfg.Width, cfg.Height, crop)
		ascii := grid.ToASCII(cfg.Charset, cfg.Invert)
		frames[i] = Frame{Grid: ascii, Delay: delay, Info: FrameInfo{Index: i}}
	}
	return frames
}

// ─── Pulse (Brightness Oscillation) ──────────────────────────────────────

func animatePulse(img image.Image, cfg Config, n int) []Frame {
	baseGrid := ToGrayscale(img, cfg.Width, cfg.Height)
	frames := make([]Frame, n)
	delay := cfg.autoDelay()
	charset := cfg.Charset
	clen := len(charset)
	if clen == 0 {
		clen = 1
	}

	for i := 0; i < n; i++ {
		t := float64(i) / float64(n)
		phase := math.Sin(t * 2 * math.Pi * 2)
		mult := 1.0 + phase*0.3

		rows := make([]string, cfg.Height)
		for y, row := range baseGrid {
			buf := make([]byte, cfg.Width)
			for x, p := range row {
				gray := float64(p.Gray) * mult
				if cfg.Invert {
					gray = 255 - gray
				}
				gc := clampInt(int(gray), 0, 255)
				idx := gc * (clen - 1) / 255
				if idx >= clen {
					idx = clen - 1
				}
				buf[x] = charset[idx]
			}
			rows[y] = string(buf)
		}
		frames[i] = Frame{Grid: rows, Delay: delay, Info: FrameInfo{Index: i}}
	}
	return frames
}

// ─── Scan Reveal ────────────────────────────────────────────────────────

func animateScan(img image.Image, cfg Config, n int) []Frame {
	baseASCII := ToGrayscale(img, cfg.Width, cfg.Height).ToASCII(cfg.Charset, cfg.Invert)
	frames := make([]Frame, n)
	delay := cfg.autoDelay()

	for i := 0; i < n; i++ {
		t := float64(i) / float64(n-1)
		scanLine := int(t * float64(cfg.Height))
		if scanLine >= cfg.Height {
			scanLine = cfg.Height - 1
		}

		rows := make([]string, cfg.Height)
		for y := 0; y < cfg.Height; y++ {
			if y <= scanLine {
				rows[y] = baseASCII[y]
			} else {
				rows[y] = strings.Repeat(" ", cfg.Width)
			}
		}
		frames[i] = Frame{Grid: rows, Delay: delay, Info: FrameInfo{Index: i}}
	}
	return frames
}

// ─── Ripple (Sine-Wave Row Distortion) ───────────────────────────────────

func animateRipple(img image.Image, cfg Config, n int) []Frame {
	baseGrid := ToGrayscale(img, cfg.Width, cfg.Height)
	frames := make([]Frame, n)
	delay := cfg.autoDelay()
	charset := cfg.Charset
	clen := len(charset)
	if clen == 0 {
		clen = 1
	}
	w := cfg.Width
	h := cfg.Height

	for i := 0; i < n; i++ {
		t := float64(i) / float64(n)
		phase := t * 2 * math.Pi

		rows := make([]string, h)
		for y := 0; y < h; y++ {
			buf := make([]byte, w)
			for x := 0; x < w; x++ {
				offset := int(math.Round(2.0 * math.Sin(float64(x)*0.3+phase*3)))
				sy := y + offset
				if sy < 0 {
					sy = 0
				}
				if sy >= h {
					sy = h - 1
				}

				p := baseGrid[sy][x]
				gray := int(p.Gray)
				if cfg.Invert {
					gray = 255 - gray
				}
				idx := gray * (clen - 1) / 255
				if idx >= clen {
					idx = clen - 1
				}
				buf[x] = charset[idx]
			}
			rows[y] = string(buf)
		}
		frames[i] = Frame{Grid: rows, Delay: delay, Info: FrameInfo{Index: i}}
	}
	return frames
}

// ─── Glitch ──────────────────────────────────────────────────────────────

func animateGlitch(img image.Image, cfg Config, n int) []Frame {
	baseASCII := ToGrayscale(img, cfg.Width, cfg.Height).ToASCII(cfg.Charset, cfg.Invert)
	frames := make([]Frame, n)
	delay := cfg.autoDelay()

	for i := 0; i < n; i++ {
		t := float64(i) / float64(n-1)
		intensity := 0.3 + 0.4*math.Sin(t*math.Pi*4)
		intensity *= intensity

		rows := make([]string, cfg.Height)
		copy(rows, baseASCII)

		numGlitched := int(float64(cfg.Height) * intensity)
		for g := 0; g < numGlitched; g++ {
			ry := absInt(hashInt(i*cfg.Height+g)) % cfg.Height
			shift := absInt(hashInt(i*cfg.Width+g)) % 6

			row := []byte(rows[ry])
			if len(row) <= shift {
				continue
			}
			newRow := make([]byte, len(row))
			copy(newRow[shift:], row[:len(row)-shift])
			copy(newRow[:shift], row[len(row)-shift:])
			if shift%2 == 0 {
				for k := 0; k < 3 && k < len(newRow); k++ {
					newRow[(hashInt(ry*100+k)*7)%len(newRow)] = cfg.Charset[(hashInt(ry*100+k)*3)%len(cfg.Charset)]
				}
			}
			rows[ry] = string(newRow)
		}
		frames[i] = Frame{Grid: rows, Delay: delay, Info: FrameInfo{Index: i}}
	}
	return frames
}

// ─── Dissolve (charset crossfade) ────────────────────────────────────────

func animateDissolve(img image.Image, cfg Config, n int) []Frame {
	baseGrid := ToGrayscale(img, cfg.Width, cfg.Height)
	frames := make([]Frame, n)
	delay := cfg.autoDelay()
	h := cfg.Height
	w := cfg.Width

	charsets := []string{
		MinimalCharset,
		StrokeCharset,
		StandardCharset,
		DenseCharset,
	}

	for i := 0; i < n; i++ {
		t := float64(i) / float64(n-1)
		csIdx := int(t * float64(len(charsets)-1))
		csFrac := t*float64(len(charsets)-1) - float64(csIdx)
		if csIdx >= len(charsets)-1 {
			csIdx = len(charsets) - 2
			csFrac = 1.0
		}

		csA := charsets[csIdx]
		csB := charsets[csIdx+1]
		clenA := maxInt(len(csA), 1)
		clenB := maxInt(len(csB), 1)

		rows := make([]string, h)
		for y, row := range baseGrid {
			buf := make([]byte, w)
			for x, p := range row {
				gray := int(p.Gray)
				if cfg.Invert {
					gray = 255 - gray
				}
				idxA := gray * (clenA - 1) / 255
				idxB := gray * (clenB - 1) / 255
				if idxA >= clenA {
					idxA = clenA - 1
				}
				if idxB >= clenB {
					idxB = clenB - 1
				}
				threshold := csFrac
				noise := float64(hashInt(y*h+x*3+i*7)) / 65536.0
				if noise < threshold {
					buf[x] = csB[idxB]
				} else {
					buf[x] = csA[idxA]
				}
			}
			rows[y] = string(buf)
		}
		frames[i] = Frame{Grid: rows, Delay: delay, Info: FrameInfo{Index: i}}
	}
	return frames
}

// ─── Breath (Scale Pulse) ────────────────────────────────────────────────

func animateBreath(img image.Image, cfg Config, n int) []Frame {
	frames := make([]Frame, n)
	delay := cfg.autoDelay()
	bounds := img.Bounds()
	srcW := float64(bounds.Dx())
	srcH := float64(bounds.Dy())
	fx, fy := cfg.FocalX, cfg.FocalY

	for i := 0; i < n; i++ {
		t := float64(i) / float64(n)
		phase := math.Sin(t * 2 * math.Pi * 1.5)
		scale := 1.0 + phase*0.12

		cropW := cfg.Scale / scale
		cropH := cfg.Scale / scale
		imgAspect := srcW / srcH
		cellAspect := float64(cfg.Width) / float64(cfg.Height)
		if imgAspect > cellAspect {
			cropH = cropW * cellAspect / imgAspect
		} else {
			cropW = cropH * imgAspect / cellAspect
		}

		crop := CropRect{
			X: fx - cropW/2,
			Y: fy - cropH/2,
			W: cropW,
			H: cropH,
		}

		grid := ToGrayscaleCrop(img, cfg.Width, cfg.Height, crop)
		ascii := grid.ToASCII(cfg.Charset, cfg.Invert)
		frames[i] = Frame{Grid: ascii, Delay: delay, Info: FrameInfo{Index: i}}
	}
	return frames
}

// ─── Orbit (Focal Point Rotation) ────────────────────────────────────────

func animateOrbit(img image.Image, cfg Config, n int) []Frame {
	frames := make([]Frame, n)
	delay := cfg.autoDelay()
	bounds := img.Bounds()
	srcW := float64(bounds.Dx())
	srcH := float64(bounds.Dy())
	radius := 0.15

	for i := 0; i < n; i++ {
		t := float64(i) / float64(n)
		angle := t * 2 * math.Pi

		fx := 0.5 + radius*math.Cos(angle)
		fy := 0.5 + radius*math.Sin(angle)
		fx = normalizeClamp(fx)
		fy = normalizeClamp(fy)

		scale := cfg.Scale * 0.85
		cropW := scale
		cropH := scale
		imgAspect := srcW / srcH
		cellAspect := float64(cfg.Width) / float64(cfg.Height)
		if imgAspect > cellAspect {
			cropH = cropW * cellAspect / imgAspect
		} else {
			cropW = cropH * imgAspect / cellAspect
		}

		crop := CropRect{
			X: fx - cropW/2,
			Y: fy - cropH/2,
			W: cropW,
			H: cropH,
		}

		grid := ToGrayscaleCrop(img, cfg.Width, cfg.Height, crop)
		ascii := grid.ToASCII(cfg.Charset, cfg.Invert)
		frames[i] = Frame{Grid: ascii, Delay: delay, Info: FrameInfo{Index: i}}
	}
	return frames
}

// ─── Utility ─────────────────────────────────────────────────────────────

func easeInOutCubic(t float64) float64 {
	if t < 0.5 {
		return 4 * t * t * t
	}
	return 1 - math.Pow(-2*t+2, 3)/2
}

func absInt(n int) int {
	if n < 0 {
		return -n
	}
	return n
}

func maxInt(a, b int) int {
	if a > b {
		return a
	}
	return b
}

// hashInt returns a deterministic pseudo-random int from an int seed.
func hashInt(seed int) int {
	h := uint32(seed*2654435761) ^ uint32(seed*2246822519)
	h ^= h >> 16
	h *= 0x45d9f3b
	h ^= h >> 16
	return int(h)
}
