package tui

import "math"

type djoint struct{ x, y float64 }

type dancePose struct {
	head   djoint
	neck   djoint
	lElbow djoint
	rElbow djoint
	lHand  djoint
	rHand  djoint
	hip    djoint
	lKnee  djoint
	rKnee  djoint
	lFoot  djoint
	rFoot  djoint
}

func j(x, y float64) djoint { return djoint{x, y} }

var dancePoses = []dancePose{
	{ // 0: neutral standing
		j(0.50, 0.08), j(0.50, 0.17),
		j(0.38, 0.30), j(0.62, 0.30), j(0.36, 0.42), j(0.64, 0.42),
		j(0.50, 0.50),
		j(0.44, 0.72), j(0.56, 0.72), j(0.42, 0.95), j(0.58, 0.95),
	},
	{ // 1: arms up V
		j(0.50, 0.10), j(0.50, 0.19),
		j(0.35, 0.10), j(0.65, 0.10), j(0.28, 0.02), j(0.72, 0.02),
		j(0.50, 0.52),
		j(0.44, 0.72), j(0.56, 0.72), j(0.42, 0.95), j(0.58, 0.95),
	},
	{ // 2: disco point right, wide stance
		j(0.48, 0.10), j(0.48, 0.19),
		j(0.32, 0.32), j(0.68, 0.10), j(0.28, 0.44), j(0.82, 0.04),
		j(0.50, 0.52),
		j(0.36, 0.72), j(0.64, 0.72), j(0.28, 0.95), j(0.72, 0.95),
	},
	{ // 3: disco point left
		j(0.52, 0.10), j(0.52, 0.19),
		j(0.32, 0.10), j(0.68, 0.32), j(0.18, 0.04), j(0.72, 0.44),
		j(0.50, 0.52),
		j(0.36, 0.72), j(0.64, 0.72), j(0.28, 0.95), j(0.72, 0.95),
	},
	{ // 4: jump — arms+legs spread
		j(0.50, 0.05), j(0.50, 0.14),
		j(0.30, 0.08), j(0.70, 0.08), j(0.18, 0.02), j(0.82, 0.02),
		j(0.50, 0.44),
		j(0.32, 0.60), j(0.68, 0.60), j(0.22, 0.80), j(0.78, 0.80),
	},
	{ // 5: lean back, arm out
		j(0.55, 0.11), j(0.53, 0.20),
		j(0.36, 0.30), j(0.72, 0.14), j(0.28, 0.40), j(0.85, 0.08),
		j(0.48, 0.53),
		j(0.40, 0.74), j(0.60, 0.70), j(0.35, 0.95), j(0.65, 0.95),
	},
	{ // 6: high kick
		j(0.45, 0.10), j(0.45, 0.19),
		j(0.28, 0.14), j(0.58, 0.30), j(0.18, 0.06), j(0.65, 0.42),
		j(0.45, 0.50),
		j(0.38, 0.72), j(0.62, 0.45), j(0.35, 0.95), j(0.78, 0.35),
	},
	{ // 7: groove crouch, arms bent
		j(0.50, 0.14), j(0.50, 0.23),
		j(0.32, 0.26), j(0.68, 0.26), j(0.25, 0.16), j(0.75, 0.16),
		j(0.50, 0.55),
		j(0.40, 0.74), j(0.60, 0.74), j(0.35, 0.92), j(0.65, 0.92),
	},
	{ // 8: running man LEFT — left knee up, right arm pumps
		j(0.50, 0.10), j(0.50, 0.19),
		j(0.40, 0.28), j(0.60, 0.22), j(0.45, 0.38), j(0.55, 0.14),
		j(0.50, 0.50),
		j(0.44, 0.50), j(0.56, 0.72), j(0.44, 0.65), j(0.52, 0.95),
	},
	{ // 9: running man RIGHT — right knee up, left arm pumps
		j(0.50, 0.10), j(0.50, 0.19),
		j(0.40, 0.22), j(0.60, 0.28), j(0.45, 0.14), j(0.55, 0.38),
		j(0.50, 0.50),
		j(0.44, 0.72), j(0.56, 0.50), j(0.48, 0.95), j(0.56, 0.65),
	},
	{ // 10: T-step — feet crossed, arms out
		j(0.50, 0.12), j(0.50, 0.21),
		j(0.30, 0.25), j(0.70, 0.25), j(0.18, 0.20), j(0.82, 0.20),
		j(0.50, 0.53),
		j(0.48, 0.72), j(0.52, 0.72), j(0.52, 0.95), j(0.46, 0.93),
	},
	{ // 11: shuffle slide left
		j(0.42, 0.14), j(0.44, 0.23),
		j(0.28, 0.28), j(0.60, 0.28), j(0.18, 0.22), j(0.72, 0.22),
		j(0.46, 0.55),
		j(0.32, 0.72), j(0.58, 0.74), j(0.22, 0.92), j(0.62, 0.95),
	},
	{ // 12: shuffle slide right
		j(0.58, 0.14), j(0.56, 0.23),
		j(0.40, 0.28), j(0.72, 0.28), j(0.28, 0.22), j(0.82, 0.22),
		j(0.54, 0.55),
		j(0.42, 0.74), j(0.68, 0.72), j(0.38, 0.95), j(0.78, 0.92),
	},
}

// Lying down — figure horizontal near the bottom, head left.
var restPose = dancePose{
	j(0.15, 0.82), j(0.22, 0.82),
	j(0.18, 0.76), j(0.18, 0.88), j(0.10, 0.72), j(0.10, 0.92),
	j(0.50, 0.82),
	j(0.72, 0.78), j(0.72, 0.86), j(0.88, 0.76), j(0.88, 0.88),
}

// Dance sequence mixes classic moves with house shuffle.
var danceSequence = []int{
	0, 1, 7, 1,
	8, 9, 8, 9,
	2, 3, 2, 3,
	10, 11, 10, 12,
	4, 7, 5, 6,
	8, 9, 11, 12,
}

func (v *visualizer) renderDancer() string {
	rows := v.vizRows
	dotRows := rows * 4
	dotCols := v.bars * 2

	grid := make([][]bool, dotRows)
	for r := range grid {
		grid[r] = make([]bool, dotCols)
	}

	t := float64(v.frame)
	beatPhase := math.Mod(t, beatTicks) / beatTicks
	beatNum := int(t / beatTicks)

	seq := danceSequence
	cur := seq[beatNum%len(seq)]
	nxt := seq[(beatNum+1)%len(seq)]

	eased := easeInOutCubic(beatPhase)
	pose := lerpPose(dancePoses[cur], dancePoses[nxt], eased)

	if v.playing {
		bob := math.Sin(beatPhase*math.Pi*2) * 0.012
		pose = offsetPose(pose, 0, bob)
	} else {
		// Smoothly transition to lying down over ~1 second (10 frames).
		restBlend := clampF(float64(v.frame)*0.1, 0, 1)
		pose = lerpPose(pose, restPose, easeInOutCubic(restBlend))
	}

	aspect := 0.45
	figH := float64(dotRows)
	figW := figH * aspect
	if figW > float64(dotCols)*0.8 {
		figW = float64(dotCols) * 0.8
		figH = figW / aspect
	}
	ox := (float64(dotCols) - figW) / 2
	oy := (float64(dotRows) - figH) / 2

	sx := func(nx float64) int { return int(math.Round(ox + nx*figW)) }
	sy := func(ny float64) int { return int(math.Round(oy + ny*figH)) }

	headR := max(int(figH/16), 2)
	torsoT := max(int(figW/7), 2)
	limbT := max(int(figW/11), 1)
	legT := max(int(figW/9), 1)

	fillCircle(grid, sx(pose.head.x), sy(pose.head.y), headR, dotCols, dotRows)

	drawThickLine(grid, sx(pose.neck.x), sy(pose.neck.y),
		sx(pose.hip.x), sy(pose.hip.y), torsoT, dotCols, dotRows)

	drawThickLine(grid, sx(pose.neck.x), sy(pose.neck.y),
		sx(pose.lElbow.x), sy(pose.lElbow.y), limbT, dotCols, dotRows)
	drawThickLine(grid, sx(pose.lElbow.x), sy(pose.lElbow.y),
		sx(pose.lHand.x), sy(pose.lHand.y), limbT, dotCols, dotRows)

	drawThickLine(grid, sx(pose.neck.x), sy(pose.neck.y),
		sx(pose.rElbow.x), sy(pose.rElbow.y), limbT, dotCols, dotRows)
	drawThickLine(grid, sx(pose.rElbow.x), sy(pose.rElbow.y),
		sx(pose.rHand.x), sy(pose.rHand.y), limbT, dotCols, dotRows)

	drawThickLine(grid, sx(pose.hip.x), sy(pose.hip.y),
		sx(pose.lKnee.x), sy(pose.lKnee.y), legT, dotCols, dotRows)
	drawThickLine(grid, sx(pose.lKnee.x), sy(pose.lKnee.y),
		sx(pose.lFoot.x), sy(pose.lFoot.y), legT, dotCols, dotRows)

	drawThickLine(grid, sx(pose.hip.x), sy(pose.hip.y),
		sx(pose.rKnee.x), sy(pose.rKnee.y), legT, dotCols, dotRows)
	drawThickLine(grid, sx(pose.rKnee.x), sy(pose.rKnee.y),
		sx(pose.rFoot.x), sy(pose.rFoot.y), legT, dotCols, dotRows)

	return gridToBrailleMultiRow(grid, dotCols, rows)
}

func lerpJoint(a, b djoint, t float64) djoint {
	return djoint{a.x + (b.x-a.x)*t, a.y + (b.y-a.y)*t}
}

func lerpPose(a, b dancePose, t float64) dancePose {
	return dancePose{
		head:   lerpJoint(a.head, b.head, t),
		neck:   lerpJoint(a.neck, b.neck, t),
		lElbow: lerpJoint(a.lElbow, b.lElbow, t),
		rElbow: lerpJoint(a.rElbow, b.rElbow, t),
		lHand:  lerpJoint(a.lHand, b.lHand, t),
		rHand:  lerpJoint(a.rHand, b.rHand, t),
		hip:    lerpJoint(a.hip, b.hip, t),
		lKnee:  lerpJoint(a.lKnee, b.lKnee, t),
		rKnee:  lerpJoint(a.rKnee, b.rKnee, t),
		lFoot:  lerpJoint(a.lFoot, b.lFoot, t),
		rFoot:  lerpJoint(a.rFoot, b.rFoot, t),
	}
}

func offsetPose(p dancePose, dx, dy float64) dancePose {
	off := func(j djoint) djoint { return djoint{j.x + dx, j.y + dy} }
	return dancePose{
		head: off(p.head), neck: off(p.neck),
		lElbow: off(p.lElbow), rElbow: off(p.rElbow),
		lHand: off(p.lHand), rHand: off(p.rHand),
		hip: off(p.hip),
		lKnee: off(p.lKnee), rKnee: off(p.rKnee),
		lFoot: off(p.lFoot), rFoot: off(p.rFoot),
	}
}

func easeInOutCubic(t float64) float64 {
	if t < 0.5 {
		return 4 * t * t * t
	}
	return 1 - math.Pow(-2*t+2, 3)/2
}

func fillCircle(grid [][]bool, cx, cy, r, maxC, maxR int) {
	for dy := -r; dy <= r; dy++ {
		for dx := -r; dx <= r; dx++ {
			if dx*dx+dy*dy <= r*r {
				x, y := cx+dx, cy+dy
				if x >= 0 && x < maxC && y >= 0 && y < maxR {
					grid[y][x] = true
				}
			}
		}
	}
}

func drawThickLine(grid [][]bool, x0, y0, x1, y1, thickness, maxC, maxR int) {
	dx := x1 - x0
	dy := y1 - y0
	steps := max(absInt(dx), absInt(dy))
	if steps == 0 {
		steps = 1
	}
	r := thickness / 2
	for i := range steps + 1 {
		t := float64(i) / float64(steps)
		x := int(math.Round(float64(x0) + t*float64(dx)))
		y := int(math.Round(float64(y0) + t*float64(dy)))
		for py := y - r; py <= y+r; py++ {
			for px := x - r; px <= x+r; px++ {
				if px >= 0 && px < maxC && py >= 0 && py < maxR {
					grid[py][px] = true
				}
			}
		}
	}
}

func absInt(x int) int {
	if x < 0 {
		return -x
	}
	return x
}
