package tui

import "math"

func (v *visualizer) renderRadial() string {
	rows := v.vizRows
	dotRows := rows * 4
	dotCols := v.bars * 2
	cx := float64(dotCols) / 2
	cy := float64(dotRows) / 2
	maxR := math.Min(cx, cy) - 1
	if maxR < 2 {
		maxR = 2
	}

	grid := make([][]bool, dotRows)
	for r := range grid {
		grid[r] = make([]bool, dotCols)
	}

	n := v.bars
	for i := range n {
		angle := 2 * math.Pi * float64(i) / float64(n)
		energy := v.heights[i] / maxHeight

		innerR := maxR * 0.3
		outerR := innerR + (maxR-innerR)*energy

		pulse := 1.0 + 0.08*math.Sin(float64(v.frame)*0.3)
		outerR *= pulse

		steps := max(int(outerR-innerR+1), 1)
		for s := range steps {
			r := innerR + float64(s)
			px := cx + r*math.Cos(angle)
			py := cy + r*math.Sin(angle)
			ix, iy := int(math.Round(px)), int(math.Round(py))
			if ix >= 0 && ix < dotCols && iy >= 0 && iy < dotRows {
				grid[iy][ix] = true
			}
		}

		// Ring outline at innerR
		ringSteps := max(int(2*math.Pi*innerR/float64(n)*2), 1)
		for s := range ringSteps {
			a := angle + 2*math.Pi/float64(n)*float64(s)/float64(ringSteps)
			px := cx + innerR*math.Cos(a)
			py := cy + innerR*math.Sin(a)
			ix, iy := int(math.Round(px)), int(math.Round(py))
			if ix >= 0 && ix < dotCols && iy >= 0 && iy < dotRows {
				grid[iy][ix] = true
			}
		}
	}

	return gridToBrailleMultiRow(grid, dotCols, rows)
}

func vizModeName(m vizMode) string {
	names := [...]string{
		"equalizer", "wave", "helix",
		"waterfall", "radial", "oscilloscope",
		"particles", "flame", "ipod", "007",
	}
	if int(m) < len(names) {
		return names[m]
	}
	return "?"
}

func (v *visualizer) modeName() string {
	return vizModeName(v.mode)
}
