package tui

import (
	"math"
	"strings"
)

var flameBlocks = [...]rune{' ', '░', '▒', '▓', '█'}

func (v *visualizer) tickFlame(playing bool) {
	rows := v.vizRows
	cols := v.bars
	if rows < 1 || cols < 1 {
		return
	}

	if len(v.heat) != rows || (len(v.heat) > 0 && len(v.heat[0]) != cols) {
		v.heat = make([][]float64, rows)
		for r := range v.heat {
			v.heat[r] = make([]float64, cols)
		}
	}

	// Propagate heat upward: each cell gets heat from below with decay.
	for r := 0; r < rows-1; r++ {
		for c := range cols {
			below := v.heat[r+1][c]
			// Pull from neighbors for turbulence.
			left := below
			right := below
			if c > 0 {
				left = v.heat[r+1][c-1]
			}
			if c < cols-1 {
				right = v.heat[r+1][c+1]
			}
			// Weighted average with slight randomness.
			avg := (below*0.6 + left*0.2 + right*0.2)
			jitter := prand(v.frame+r, c) * 0.1
			decay := 0.85 + jitter*0.1
			v.heat[r][c] = avg * decay
		}
	}

	// Inject energy at the bottom row from band heights.
	if playing {
		for c := range cols {
			energy := v.heights[c] / maxHeight
			// Boost with randomness for flicker.
			boost := energy * (0.8 + prand(v.frame, c+1000)*0.4)
			v.heat[rows-1][c] = clampF(boost, 0, 1)
		}
	} else {
		for c := range cols {
			v.heat[rows-1][c] *= 0.8
		}
	}
}

func (v *visualizer) renderFlame() string {
	rows := v.vizRows
	cols := v.bars
	if rows < 1 || cols < 1 || len(v.heat) != rows {
		return ""
	}

	var sb strings.Builder
	sb.Grow(rows * (cols + 1))

	for r := range rows {
		if r > 0 {
			sb.WriteByte('\n')
		}
		for c := range cols {
			h := v.heat[r][c]
			idx := max(0, min(int(math.Round(h*float64(len(flameBlocks)-1))), len(flameBlocks)-1))
			sb.WriteRune(flameBlocks[idx])
		}
	}
	return sb.String()
}
