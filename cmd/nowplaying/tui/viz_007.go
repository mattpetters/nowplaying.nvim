package tui

import "math"

var bondPoses = []dancePose{
	{ // 0: classic gun barrel stance — facing right, pistol extended
		j(0.45, 0.08), j(0.45, 0.17),
		j(0.28, 0.20), j(0.62, 0.12), j(0.18, 0.28), j(0.80, 0.08),
		j(0.44, 0.50),
		j(0.40, 0.72), j(0.52, 0.72), j(0.38, 0.95), j(0.54, 0.95),
	},
	{ // 1: walking stride — left foot forward
		j(0.50, 0.07), j(0.50, 0.16),
		j(0.38, 0.24), j(0.60, 0.28), j(0.30, 0.32), j(0.56, 0.40),
		j(0.50, 0.48),
		j(0.36, 0.68), j(0.62, 0.72), j(0.26, 0.92), j(0.68, 0.95),
	},
	{ // 2: walking stride — right foot forward
		j(0.50, 0.07), j(0.50, 0.16),
		j(0.40, 0.28), j(0.62, 0.24), j(0.44, 0.40), j(0.70, 0.32),
		j(0.50, 0.48),
		j(0.38, 0.72), j(0.64, 0.68), j(0.32, 0.95), j(0.74, 0.92),
	},
	{ // 3: hand on hip, gun up — classic pose
		j(0.48, 0.07), j(0.48, 0.16),
		j(0.32, 0.22), j(0.64, 0.10), j(0.36, 0.38), j(0.72, 0.02),
		j(0.48, 0.48),
		j(0.42, 0.72), j(0.56, 0.70), j(0.40, 0.95), j(0.58, 0.95),
	},
	{ // 4: profile — looking over shoulder
		j(0.52, 0.08), j(0.50, 0.17),
		j(0.36, 0.26), j(0.62, 0.28), j(0.28, 0.18), j(0.58, 0.40),
		j(0.48, 0.50),
		j(0.44, 0.72), j(0.54, 0.72), j(0.42, 0.95), j(0.56, 0.95),
	},
	{ // 5: crouching aim — low center of gravity
		j(0.42, 0.18), j(0.44, 0.26),
		j(0.28, 0.28), j(0.62, 0.22), j(0.14, 0.24), j(0.78, 0.18),
		j(0.46, 0.52),
		j(0.32, 0.62), j(0.60, 0.66), j(0.22, 0.82), j(0.70, 0.88),
	},
	{ // 6: dramatic lean — arched back
		j(0.56, 0.10), j(0.54, 0.19),
		j(0.38, 0.14), j(0.68, 0.26), j(0.24, 0.08), j(0.72, 0.38),
		j(0.50, 0.52),
		j(0.42, 0.72), j(0.60, 0.72), j(0.38, 0.95), j(0.62, 0.95),
	},
	{ // 7: turn-and-shoot — twisting torso
		j(0.48, 0.08), j(0.48, 0.17),
		j(0.56, 0.26), j(0.64, 0.14), j(0.62, 0.38), j(0.80, 0.10),
		j(0.46, 0.50),
		j(0.38, 0.72), j(0.56, 0.72), j(0.34, 0.95), j(0.58, 0.95),
	},
	{ // 8: femme fatale — one arm up, hip cocked
		j(0.52, 0.06), j(0.50, 0.15),
		j(0.34, 0.10), j(0.64, 0.26), j(0.26, 0.02), j(0.68, 0.40),
		j(0.50, 0.48),
		j(0.44, 0.72), j(0.58, 0.70), j(0.42, 0.95), j(0.62, 0.95),
	},
	{ // 9: dual wield — both arms extended
		j(0.50, 0.08), j(0.50, 0.17),
		j(0.30, 0.14), j(0.70, 0.14), j(0.12, 0.10), j(0.88, 0.10),
		j(0.50, 0.50),
		j(0.42, 0.72), j(0.58, 0.72), j(0.38, 0.95), j(0.62, 0.95),
	},
}

var bondSequence = []int{
	0, 0, 1, 2,
	1, 2, 3, 3,
	4, 6, 8, 8,
	7, 7, 5, 5,
	9, 9, 0, 0,
	3, 6, 4, 7,
}

func (v *visualizer) render007() string {
	rows := v.vizRows
	dotRows := rows * 4
	dotCols := v.bars * 2

	grid := make([][]bool, dotRows)
	for r := range grid {
		grid[r] = make([]bool, dotCols)
	}

	t := float64(v.frame)
	poseTicks := beatTicks * 2
	beatPhase := math.Mod(t, poseTicks) / poseTicks
	beatNum := int(t / poseTicks)

	seq := bondSequence
	cur := seq[beatNum%len(seq)]
	nxt := seq[(beatNum+1)%len(seq)]

	eased := easeInOutCubic(beatPhase)
	pose := lerpPose(bondPoses[cur], bondPoses[nxt], eased)

	sway := math.Sin(float64(v.frame)*0.08) * 0.006
	pose = offsetPose(pose, sway, 0)

	const poseAspect = 0.50
	figH := float64(dotRows) * 0.95
	figW := figH * poseAspect
	if figW > float64(dotCols)*0.90 {
		figW = float64(dotCols) * 0.90
		figH = figW / poseAspect
	}
	ox := (float64(dotCols) - figW) / 2
	oy := (float64(dotRows) - figH) / 2

	sx := func(nx float64) int { return int(math.Round(ox + nx*figW)) }
	sy := func(ny float64) int { return int(math.Round(oy + ny*figH)) }
	rad := func(w float64) int { return max(int(math.Round(w*figH/2)), 1) }

	headR := max(rad(0.060*1.8), 2)
	neckR := max(rad(0.03), 1)
	shR := max(rad(0.16), 2)
	bustR := max(rad(0.26), 3)
	waR := max(rad(0.04), 1)
	hiR := max(rad(0.24), 3)
	uaR := max(rad(0.014), 1)
	laR := max(rad(0.010), 1)
	haR := max(rad(0.008), 1)
	ulR := max(rad(0.035), 2)
	llR := max(rad(0.020), 1)
	ftR := max(rad(0.014), 1)

	if bustR < waR+2 {
		bustR = waR + 2
	}
	if hiR < waR+2 {
		hiR = waR + 2
	}

	hairR := headR + max(headR/2, 1)
	fillEllipse(grid, sx(pose.head.x)+1, sy(pose.head.y)-1, hairR, hairR+1, dotCols, dotRows)
	fillCircle(grid, sx(pose.head.x), sy(pose.head.y), headR, dotCols, dotRows)

	drawTaperedLine(grid, sx(pose.head.x), sy(pose.head.y)+headR,
		sx(pose.neck.x), sy(pose.neck.y), neckR, shR, dotCols, dotRows)

	neckY := sy(pose.neck.y)
	hipY := sy(pose.hip.y)
	neckX := sx(pose.neck.x)
	hipX := sx(pose.hip.x)
	torsoLen := max(hipY-neckY, 6)
	bustY := neckY + torsoLen*20/100
	bustX := neckX + (hipX-neckX)*20/100
	waistY := neckY + torsoLen*50/100
	waistX := neckX + (hipX-neckX)*50/100

	drawTaperedLine(grid, neckX, neckY, bustX, bustY, shR, bustR, dotCols, dotRows)
	drawTaperedLine(grid, bustX, bustY, waistX, waistY, bustR, waR, dotCols, dotRows)
	drawTaperedLine(grid, waistX, waistY, hipX, hipY, waR, hiR, dotCols, dotRows)

	bustSpread := max(bustR*3/4, 2)
	bustCircRx := max(bustR/2, 2)
	bustCircRy := max(bustCircRx*2/3, 1)
	fillEllipse(grid, bustX-bustSpread, bustY, bustCircRx, bustCircRy, dotCols, dotRows)
	fillEllipse(grid, bustX+bustSpread, bustY, bustCircRx, bustCircRy, dotCols, dotRows)

	drawTaperedLine(grid, neckX, neckY,
		sx(pose.lElbow.x), sy(pose.lElbow.y), uaR, laR, dotCols, dotRows)
	drawTaperedLine(grid, sx(pose.lElbow.x), sy(pose.lElbow.y),
		sx(pose.lHand.x), sy(pose.lHand.y), laR, haR, dotCols, dotRows)
	drawTaperedLine(grid, neckX, neckY,
		sx(pose.rElbow.x), sy(pose.rElbow.y), uaR, laR, dotCols, dotRows)
	drawTaperedLine(grid, sx(pose.rElbow.x), sy(pose.rElbow.y),
		sx(pose.rHand.x), sy(pose.rHand.y), laR, haR, dotCols, dotRows)

	drawTaperedLine(grid, hipX, hipY,
		sx(pose.lKnee.x), sy(pose.lKnee.y), ulR, llR, dotCols, dotRows)
	drawTaperedLine(grid, sx(pose.lKnee.x), sy(pose.lKnee.y),
		sx(pose.lFoot.x), sy(pose.lFoot.y), llR, ftR, dotCols, dotRows)
	drawTaperedLine(grid, hipX, hipY,
		sx(pose.rKnee.x), sy(pose.rKnee.y), ulR, llR, dotCols, dotRows)
	drawTaperedLine(grid, sx(pose.rKnee.x), sy(pose.rKnee.y),
		sx(pose.rFoot.x), sy(pose.rFoot.y), llR, ftR, dotCols, dotRows)

	return gridToBrailleMultiRow(grid, dotCols, rows)
}
