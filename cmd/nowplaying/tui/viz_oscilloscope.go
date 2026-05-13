package tui

import "math"

func (v *visualizer) renderOscilloscope() string {
	rows := v.vizRows
	dotRows := rows * 4
	dotCols := v.bars * 2

	grid := make([][]bool, dotRows)
	for r := range grid {
		grid[r] = make([]bool, dotCols)
	}

	mid := float64(dotRows) / 2
	amp := float64(dotRows)/2 - 1

	samples := v.rawSamples
	hasSamples := len(samples) > 0

	for c := range dotCols {
		var val float64
		if hasSamples {
			pos := float64(c) / float64(dotCols) * float64(len(samples)-1)
			lo := int(pos)
			if lo >= len(samples)-1 {
				val = samples[len(samples)-1]
			} else {
				frac := pos - float64(lo)
				val = samples[lo]*(1-frac) + samples[lo+1]*frac
			}
		} else {
			t := float64(v.frame)*0.15 + float64(c)*0.12
			bass := v.heights[0] / maxHeight
			treble := v.heights[min(v.bars-1, v.bars*3/4)] / maxHeight
			val = (bass*0.7 + 0.3) * math.Sin(t) * 0.8
			val += treble * 0.3 * math.Sin(t*3.7+1.2)
		}

		y := mid - val*amp
		iy := int(math.Round(y))
		if iy >= 0 && iy < dotRows {
			grid[iy][c] = true
		}
		// Thicken: fill between center and sample for visual weight.
		iy2 := int(math.Round(mid))
		if iy < iy2 {
			for r := iy + 1; r < min(iy+2, dotRows); r++ {
				grid[r][c] = true
			}
		} else if iy > iy2 {
			for r := max(iy-1, 0); r < iy; r++ {
				grid[r][c] = true
			}
		}
	}

	// Draw center line (zero crossing) as dots.
	midRow := int(math.Round(mid))
	if midRow >= 0 && midRow < dotRows {
		for c := 0; c < dotCols; c += 4 {
			grid[midRow][c] = true
		}
	}

	return gridToBrailleMultiRow(grid, dotCols, rows)
}
