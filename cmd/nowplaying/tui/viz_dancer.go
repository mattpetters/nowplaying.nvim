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
	{ // 0: hands on hips — classic Bond girl stance, arms clear of torso
		j(0.50, 0.08), j(0.50, 0.17),
		j(0.30, 0.32), j(0.70, 0.32), j(0.34, 0.44), j(0.66, 0.44),
		j(0.50, 0.50),
		j(0.44, 0.72), j(0.56, 0.72), j(0.42, 0.95), j(0.58, 0.95),
	},
	{ // 1: arms up V — shows waist
		j(0.50, 0.10), j(0.50, 0.19),
		j(0.32, 0.08), j(0.68, 0.08), j(0.22, 0.02), j(0.78, 0.02),
		j(0.50, 0.52),
		j(0.44, 0.72), j(0.56, 0.72), j(0.42, 0.95), j(0.58, 0.95),
	},
	{ // 2: hip pop right — S-curve, hand on hip
		j(0.48, 0.10), j(0.48, 0.19),
		j(0.28, 0.30), j(0.70, 0.08), j(0.32, 0.42), j(0.82, 0.02),
		j(0.54, 0.52),
		j(0.40, 0.72), j(0.62, 0.70), j(0.36, 0.95), j(0.66, 0.95),
	},
	{ // 3: hip pop left — mirror S-curve
		j(0.52, 0.10), j(0.52, 0.19),
		j(0.30, 0.08), j(0.72, 0.30), j(0.18, 0.02), j(0.68, 0.42),
		j(0.46, 0.52),
		j(0.38, 0.70), j(0.60, 0.72), j(0.34, 0.95), j(0.64, 0.95),
	},
	{ // 4: jump — arms+legs spread
		j(0.50, 0.05), j(0.50, 0.14),
		j(0.26, 0.06), j(0.74, 0.06), j(0.14, 0.02), j(0.86, 0.02),
		j(0.50, 0.44),
		j(0.30, 0.58), j(0.70, 0.58), j(0.20, 0.78), j(0.80, 0.78),
	},
	{ // 5: arched lean — hand behind head
		j(0.56, 0.10), j(0.54, 0.19),
		j(0.38, 0.12), j(0.72, 0.14), j(0.44, 0.04), j(0.86, 0.08),
		j(0.48, 0.52),
		j(0.40, 0.74), j(0.60, 0.70), j(0.35, 0.95), j(0.65, 0.95),
	},
	{ // 6: high kick — leg up, arms wide
		j(0.45, 0.10), j(0.45, 0.19),
		j(0.24, 0.12), j(0.62, 0.28), j(0.12, 0.04), j(0.70, 0.40),
		j(0.45, 0.50),
		j(0.38, 0.72), j(0.66, 0.42), j(0.35, 0.95), j(0.82, 0.30),
	},
	{ // 7: groove crouch — hands on knees, low center
		j(0.50, 0.16), j(0.50, 0.25),
		j(0.28, 0.28), j(0.72, 0.28), j(0.22, 0.18), j(0.78, 0.18),
		j(0.50, 0.56),
		j(0.38, 0.74), j(0.62, 0.74), j(0.34, 0.92), j(0.66, 0.92),
	},
	{ // 8: shimmy left — hips shifted, arms flowing
		j(0.48, 0.10), j(0.48, 0.19),
		j(0.28, 0.16), j(0.64, 0.24), j(0.16, 0.10), j(0.70, 0.34),
		j(0.46, 0.50),
		j(0.38, 0.72), j(0.56, 0.72), j(0.34, 0.95), j(0.58, 0.95),
	},
	{ // 9: shimmy right — mirror
		j(0.52, 0.10), j(0.52, 0.19),
		j(0.36, 0.24), j(0.72, 0.16), j(0.30, 0.34), j(0.84, 0.10),
		j(0.54, 0.50),
		j(0.44, 0.72), j(0.62, 0.72), j(0.42, 0.95), j(0.66, 0.95),
	},
	{ // 10: T-step — feet crossed, arms wide
		j(0.50, 0.12), j(0.50, 0.21),
		j(0.26, 0.22), j(0.74, 0.22), j(0.14, 0.16), j(0.86, 0.16),
		j(0.50, 0.53),
		j(0.48, 0.72), j(0.52, 0.72), j(0.52, 0.95), j(0.46, 0.93),
	},
	{ // 11: sway left — hip out, arms trailing
		j(0.44, 0.12), j(0.46, 0.21),
		j(0.24, 0.26), j(0.64, 0.18), j(0.12, 0.20), j(0.76, 0.10),
		j(0.44, 0.54),
		j(0.32, 0.72), j(0.56, 0.74), j(0.24, 0.94), j(0.60, 0.95),
	},
	{ // 12: sway right — mirror
		j(0.56, 0.12), j(0.54, 0.21),
		j(0.36, 0.18), j(0.76, 0.26), j(0.24, 0.10), j(0.88, 0.20),
		j(0.56, 0.54),
		j(0.44, 0.74), j(0.68, 0.72), j(0.40, 0.95), j(0.76, 0.94),
	},
}

var danceSequence = []int{
	0, 1, 0, 1,
	2, 3, 2, 3,
	8, 9, 8, 9,
	10, 11, 10, 12,
	4, 7, 5, 6,
	1, 0, 11, 12,
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
	x := -2*t + 2
	return 1 - (x*x*x)/2
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

func fillEllipse(grid [][]bool, cx, cy, rx, ry, maxC, maxR int) {
	if rx < 1 {
		rx = 1
	}
	if ry < 1 {
		ry = 1
	}
	for dy := -ry; dy <= ry; dy++ {
		for dx := -rx; dx <= rx; dx++ {
			if float64(dx*dx)/float64(rx*rx)+float64(dy*dy)/float64(ry*ry) <= 1.0 {
				x, y := cx+dx, cy+dy
				if x >= 0 && x < maxC && y >= 0 && y < maxR {
					grid[y][x] = true
				}
			}
		}
	}
}

func drawTaperedLine(grid [][]bool, x0, y0, x1, y1, r0, r1, maxC, maxR int) {
	dx := x1 - x0
	dy := y1 - y0
	steps := max(absInt(dx), absInt(dy))
	if steps == 0 {
		steps = 1
	}
	for i := range steps + 1 {
		t := float64(i) / float64(steps)
		x := int(math.Round(float64(x0) + t*float64(dx)))
		y := int(math.Round(float64(y0) + t*float64(dy)))
		r := int(math.Round(float64(r0) + t*float64(r1-r0)))
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
