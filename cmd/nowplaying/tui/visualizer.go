package tui

import (
	"math"
	"strings"
)

const brailleBase = 0x2800

// barRunes maps a bar height (0–8) to a braille character with both
// columns filled from the bottom up. Two stacked braille chars per bar
// gives 8 dot-rows of vertical resolution.
var barRunes = [5]rune{
	0x2800, // 0: empty
	0x28C0, // 1: ⣀ bottom row
	0x28E4, // 2: ⣤ bottom 2 rows
	0x28F6, // 3: ⣶ bottom 3 rows
	0x28FF, // 4: ⣿ all rows
}

type vizMode int

const (
	vizEqualizer vizMode = iota
	vizWave
	vizHelix
	vizWaterfall
	vizRadial
	vizOscilloscope
	vizParticles
	vizFlame
	vizDancer
)

const vizModeCount = 9

type particle struct {
	x, y   float64
	vy     float64
	life   int
	bright float64
}

const (
	maxHeight = 8.0
	gravity   = 0.12
	peakHold  = 12
	peakDecay = 0.08

	// Beat simulation: ~128 BPM = ~4.7 ticks per beat at 100ms tick.
	beatTicks  = 4.7
	hitWindow  = 0.25 // fraction of beat period that counts as a "hit"
	barDecay   = 0.82 // per-tick exponential decay between beats
	spikeSnap  = 0.85 // how fast bars snap to spike target on a hit
)

const feedStaleFrames = 2 // 200ms at 100ms tick rate

type visualizer struct {
	mode    vizMode
	frame   int
	bars    int
	vizRows int
	playing bool
	heights []float64
	peaks   []float64
	holds   []int

	realBands     []float64
	rawSamples    []float64
	hasRealData   bool
	lastFeedFrame int

	wfBuf  [][]float64
	wfHead int
	wfLen  int

	particles []particle

	heat [][]float64
}

func newVisualizer(width, rows int) *visualizer {
	bars := clampBars(width)
	if rows < 2 {
		rows = 2
	}
	return &visualizer{
		bars:    bars,
		vizRows: rows,
		heights: make([]float64, bars),
		peaks:   make([]float64, bars),
		holds:   make([]int, bars),
	}
}

func (v *visualizer) resize(width, rows int) {
	bars := clampBars(width)
	if rows < 2 {
		rows = 2
	}
	v.vizRows = rows
	if bars != v.bars {
		v.bars = bars
		v.heights = resizeSlice(v.heights, bars)
		v.peaks = resizeSlice(v.peaks, bars)
		v.holds = resizeIntSlice(v.holds, bars)
		v.wfBuf = nil
		v.wfHead = 0
		v.wfLen = 0
		v.heat = nil
	}
}

func (v *visualizer) tick(playing bool) {
	v.frame++
	v.playing = playing
	if playing {
		v.tickPlaying()
	} else {
		v.tickPaused()
	}
	switch v.mode {
	case vizWaterfall:
		v.tickWaterfall()
	case vizParticles:
		v.tickParticles(playing)
	case vizFlame:
		v.tickFlame(playing)
	}
}

func (v *visualizer) tickPlaying() {
	if v.feedFresh() {
		v.tickRealSpectrum()
	} else {
		v.tickSimulated()
	}
}

func (v *visualizer) tickRealSpectrum() {
	for i := 0; i < v.bars; i++ {
		target := v.realBands[i] * maxHeight
		v.heights[i] += (target - v.heights[i]) * spikeSnap
		v.heights[i] = clampF(v.heights[i], 0, maxHeight)
		v.updatePeak(i)
	}
}

func (v *visualizer) tickSimulated() {
	t := float64(v.frame)
	beatPhase := math.Mod(t, beatTicks) / beatTicks
	isHit := beatPhase < hitWindow
	beatNum := int(t / beatTicks)

	for i := 0; i < v.bars; i++ {
		band := float64(i) / float64(v.bars)

		if isHit {
			energy := v.beatEnergy(i, beatNum, band)
			target := energy * maxHeight
			v.heights[i] += (target - v.heights[i]) * spikeSnap
		} else {
			v.heights[i] *= barDecay
			if band > 0.5 {
				noise := prand(v.frame, i) * 2.5 * band
				if noise > v.heights[i] {
					v.heights[i] = noise
				}
			}
		}
		v.heights[i] = clampF(v.heights[i], 0, maxHeight)
		v.updatePeak(i)
	}
}

func (v *visualizer) updatePeak(i int) {
	if v.heights[i] >= v.peaks[i] {
		v.peaks[i] = v.heights[i]
		v.holds[i] = peakHold
	} else if v.holds[i] > 0 {
		v.holds[i]--
	} else {
		v.peaks[i] -= peakDecay
		if v.peaks[i] < v.heights[i] {
			v.peaks[i] = v.heights[i]
		}
	}
}

func (v *visualizer) tickPaused() {
	for i := 0; i < v.bars; i++ {
		rate := gravity * (0.7 + 0.6*float64(i%5)/4.0)
		v.heights[i] -= rate
		if v.heights[i] < 0 {
			v.heights[i] = 0
		}
		v.peaks[i] -= peakDecay * 2
		if v.peaks[i] < 0 {
			v.peaks[i] = 0
		}
		v.holds[i] = 0
	}
}

// beatEnergy returns 0.0–1.0 energy for bar i on the given beat.
// Simulates a drum pattern: kick drives bass, snare drives mids,
// hi-hat drives treble — each on different beat subdivisions.
func (v *visualizer) beatEnergy(i, beatNum int, band float64) float64 {
	// Slow phrase modulation so it doesn't feel perfectly static.
	phrase := float64(beatNum) * 0.07
	envelope := 0.6 + 0.4*math.Sin(phrase+float64(i)*0.15)

	var energy float64

	switch {
	case band < 0.3:
		// Bass / kick: hits on beats 0 and 2 of a 4-beat bar.
		kick := beatNum % 4
		if kick == 0 || kick == 2 {
			energy = 0.7 + prand(beatNum, i)*0.3
		} else {
			energy = prand(beatNum, i) * 0.25
		}
	case band < 0.6:
		// Mids / snare: hits on beats 1 and 3.
		snare := beatNum % 4
		if snare == 1 || snare == 3 {
			energy = 0.6 + prand(beatNum, i)*0.3
		} else {
			energy = 0.15 + prand(beatNum, i)*0.2
		}
	default:
		// Treble / hi-hat: every beat + random off-beats.
		energy = 0.3 + prand(beatNum, i)*0.5
		// Accent every other beat.
		if beatNum%2 == 0 {
			energy += 0.15
		}
	}

	return clampF(energy*envelope, 0, 1)
}

// prand returns a deterministic pseudo-random value in [0, 1) from two
// integer seeds. No math/rand needed — just a fast integer hash.
func prand(a, b int) float64 {
	h := uint32(a*2654435761) ^ uint32(b*2246822519)
	h ^= h >> 16
	h *= 0x45d9f3b
	h ^= h >> 16
	return float64(h&0xFFFF) / 65536.0
}

func (v *visualizer) feed(bands []float64, samples []float64) {
	v.realBands = resampleBands(bands, v.bars)
	if len(samples) > 0 {
		v.rawSamples = samples
	}
	v.hasRealData = true
	v.lastFeedFrame = v.frame
}

func (v *visualizer) feedFresh() bool {
	return v.hasRealData && v.frame-v.lastFeedFrame <= feedStaleFrames
}

func (v *visualizer) cycleMode() {
	v.mode = (v.mode + 1) % vizModeCount
	v.frame = 0
}

func (v *visualizer) render() string {
	switch v.mode {
	case vizWave:
		return v.renderWave()
	case vizHelix:
		return v.renderHelix()
	case vizWaterfall:
		return v.renderWaterfall()
	case vizRadial:
		return v.renderRadial()
	case vizOscilloscope:
		return v.renderOscilloscope()
	case vizParticles:
		return v.renderParticles()
	case vizFlame:
		return v.renderFlame()
	case vizDancer:
		return v.renderDancer()
	default:
		return v.renderEqualizer()
	}
}

// renderEqualizer draws a 2-row-tall spectrum analyzer. Each bar is a
// stack of two braille characters (bottom + top), giving 8 dot-rows of
// resolution. Peak-hold dots float above the bar.
func (v *visualizer) renderEqualizer() string {
	topRow := make([]rune, v.bars)
	botRow := make([]rune, v.bars)

	for i := 0; i < v.bars; i++ {
		h := v.heights[i]
		pk := v.peaks[i]

		// Bottom char covers dot-rows 0–3, top char covers 4–7.
		botH := clampF(h, 0, 4)
		topH := clampF(h-4, 0, 4)

		botRow[i] = barRunes[int(math.Round(botH))]
		topRow[i] = barRunes[int(math.Round(topH))]

		// Peak dot: render as a single dot in the appropriate char.
		if pk > h+0.3 {
			pkRow := min(int(math.Round(pk)), 7)
			if pkRow >= 4 {
				topRow[i] = peakOverlay(topRow[i], pkRow-4)
			} else {
				botRow[i] = peakOverlay(botRow[i], pkRow)
			}
		}
	}

	top := string(topRow)
	bot := string(botRow)
	return top + "\n" + bot
}

// peakOverlay sets both dots in a given row of a braille character,
// preserving any existing dots.
func peakOverlay(base rune, row int) rune {
	dotMap := [4]int{
		0x01 | 0x08, // row 0
		0x02 | 0x10, // row 1
		0x04 | 0x20, // row 2
		0x40 | 0x80, // row 3
	}
	if row < 0 || row > 3 {
		return base
	}
	return base | rune(dotMap[row])
}

func (v *visualizer) renderWave() string {
	const H = 4
	grid := make([][]bool, H)
	for r := range grid {
		grid[r] = make([]bool, v.bars*2)
	}

	for c := 0; c < v.bars*2; c++ {
		phase := float64(v.frame) - float64(c)*0.5
		row := int(math.Round((math.Sin(phase*0.8) + 1) / 2 * float64(H-1)))
		if row >= 0 && row < H {
			grid[row][c] = true
			if row > 0 && (v.frame+c)%3 == 0 {
				grid[row-1][c] = true
			}
		}
	}

	return gridToBraille(grid, v.bars*2)
}

func (v *visualizer) renderHelix() string {
	const H = 4
	grid := make([][]bool, H)
	for r := range grid {
		grid[r] = make([]bool, v.bars*2)
	}

	for c := 0; c < v.bars*2; c++ {
		phase := float64(v.frame+c) * (math.Pi / 4)
		y1 := int(math.Round((math.Sin(phase) + 1) / 2 * float64(H-1)))
		y2 := int(math.Round((math.Sin(phase+math.Pi) + 1) / 2 * float64(H-1)))
		if y1 >= 0 && y1 < H {
			grid[y1][c] = true
		}
		if y2 >= 0 && y2 < H {
			grid[y2][c] = true
		}
	}

	return gridToBraille(grid, v.bars*2)
}

func gridToBraille(grid [][]bool, cols int) string {
	rows := len(grid)
	charCount := (cols + 1) / 2
	var sb strings.Builder
	sb.Grow(charCount * 4)

	dotMap := [4][2]int{
		{0x01, 0x08},
		{0x02, 0x10},
		{0x04, 0x20},
		{0x40, 0x80},
	}

	for c := range charCount {
		code := brailleBase
		for r := range min(4, rows) {
			for d := range 2 {
				col := c*2 + d
				if col < cols && grid[r][col] {
					code |= dotMap[r][d]
				}
			}
		}
		sb.WriteRune(rune(code))
	}
	return sb.String()
}

func clampBars(width int) int {
	if width < 4 {
		return 4
	}
	return width
}

func clampF(v, lo, hi float64) float64 {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

func resizeSlice(s []float64, n int) []float64 {
	out := make([]float64, n)
	copy(out, s)
	return out
}

func resizeIntSlice(s []int, n int) []int {
	out := make([]int, n)
	copy(out, s)
	return out
}

func resampleBands(src []float64, n int) []float64 {
	if len(src) == 0 {
		return make([]float64, n)
	}
	if len(src) == n {
		out := make([]float64, n)
		copy(out, src)
		return out
	}
	out := make([]float64, n)
	scale := float64(len(src)-1) / float64(n-1)
	for i := range n {
		pos := float64(i) * scale
		lo := int(pos)
		if lo >= len(src)-1 {
			out[i] = src[len(src)-1]
			continue
		}
		frac := pos - float64(lo)
		out[i] = src[lo]*(1-frac) + src[lo+1]*frac
	}
	return out
}
