package tui

import "strings"

func (v *visualizer) tickWaterfall() {
	cap := max(v.vizRows*4, 4)
	if len(v.wfBuf) != cap {
		v.wfBuf = make([][]float64, cap)
		v.wfHead = 0
		v.wfLen = 0
	}
	snap := make([]float64, v.bars)
	for i := range v.bars {
		snap[i] = v.heights[i] / maxHeight
	}
	v.wfBuf[v.wfHead] = snap
	v.wfHead = (v.wfHead + 1) % cap
	if v.wfLen < cap {
		v.wfLen++
	}
}

func (v *visualizer) renderWaterfall() string {
	rows := v.vizRows
	dotRows := rows * 4
	cols := v.bars * 2

	grid := make([][]bool, dotRows)
	for r := range grid {
		grid[r] = make([]bool, cols)
	}

	cap := len(v.wfBuf)
	if cap == 0 {
		return strings.Repeat(string(rune(brailleBase)), v.bars)
	}

	drawn := min(v.wfLen, dotRows)
	for row := range drawn {
		idx := (v.wfHead - 1 - row + cap) % cap
		snap := v.wfBuf[idx]
		if snap == nil {
			continue
		}
		for col, val := range snap {
			if col*2 >= cols {
				break
			}
			if val > 0.05 {
				grid[row][col*2] = true
			}
			if val > 0.3 {
				grid[row][col*2+1] = true
			}
		}
	}

	return gridToBrailleMultiRow(grid, cols, rows)
}

func gridToBrailleMultiRow(grid [][]bool, cols, rows int) string {
	charCols := (cols + 1) / 2
	dotMap := [4][2]int{
		{0x01, 0x08},
		{0x02, 0x10},
		{0x04, 0x20},
		{0x40, 0x80},
	}

	var sb strings.Builder
	sb.Grow(rows * (charCols*4 + 1))

	for charRow := range rows {
		if charRow > 0 {
			sb.WriteByte('\n')
		}
		for charCol := range charCols {
			code := brailleBase
			for dr := range 4 {
				gridRow := charRow*4 + dr
				if gridRow >= len(grid) {
					break
				}
				for d := range 2 {
					col := charCol*2 + d
					if col < cols && grid[gridRow][col] {
						code |= dotMap[dr][d]
					}
				}
			}
			sb.WriteRune(rune(code))
		}
	}
	return sb.String()
}
