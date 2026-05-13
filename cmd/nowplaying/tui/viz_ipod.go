package tui

import "math"

const (
	headRadius = 0.055
	shoulderW  = 0.16
	waistW     = 0.10
	hipW       = 0.13
	upperArmW  = 0.035
	lowerArmW  = 0.025
	handW      = 0.020
	upperLegW  = 0.045
	lowerLegW  = 0.030
	footW      = 0.022
)

func (v *visualizer) renderIPod() string {
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

	bob := math.Sin(beatPhase*math.Pi*2) * 0.010
	pose = offsetPose(pose, 0, bob)

	const poseAspect = 0.55
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

	hR := max(rad(headRadius*2), 2)
	shR := rad(shoulderW)
	waR := rad(waistW)
	hiR := rad(hipW)
	uaR := rad(upperArmW)
	laR := rad(lowerArmW)
	haR := rad(handW)
	ulR := rad(upperLegW)
	llR := rad(lowerLegW)
	ftR := rad(footW)

	fillCircle(grid, sx(pose.head.x), sy(pose.head.y), hR, dotCols, dotRows)

	neckR := max(rad(waistW*0.6), 1)
	drawTaperedLine(grid, sx(pose.head.x), sy(pose.head.y)+hR,
		sx(pose.neck.x), sy(pose.neck.y), neckR, shR, dotCols, dotRows)

	midTorsoY := (sy(pose.neck.y) + sy(pose.hip.y)) / 2
	midTorsoX := (sx(pose.neck.x) + sx(pose.hip.x)) / 2
	drawTaperedLine(grid, sx(pose.neck.x), sy(pose.neck.y),
		midTorsoX, midTorsoY, shR, waR, dotCols, dotRows)
	drawTaperedLine(grid, midTorsoX, midTorsoY,
		sx(pose.hip.x), sy(pose.hip.y), waR, hiR, dotCols, dotRows)

	drawTaperedLine(grid, sx(pose.neck.x), sy(pose.neck.y),
		sx(pose.lElbow.x), sy(pose.lElbow.y), uaR, laR, dotCols, dotRows)
	drawTaperedLine(grid, sx(pose.lElbow.x), sy(pose.lElbow.y),
		sx(pose.lHand.x), sy(pose.lHand.y), laR, haR, dotCols, dotRows)

	drawTaperedLine(grid, sx(pose.neck.x), sy(pose.neck.y),
		sx(pose.rElbow.x), sy(pose.rElbow.y), uaR, laR, dotCols, dotRows)
	drawTaperedLine(grid, sx(pose.rElbow.x), sy(pose.rElbow.y),
		sx(pose.rHand.x), sy(pose.rHand.y), laR, haR, dotCols, dotRows)

	drawTaperedLine(grid, sx(pose.hip.x), sy(pose.hip.y),
		sx(pose.lKnee.x), sy(pose.lKnee.y), ulR, llR, dotCols, dotRows)
	drawTaperedLine(grid, sx(pose.lKnee.x), sy(pose.lKnee.y),
		sx(pose.lFoot.x), sy(pose.lFoot.y), llR, ftR, dotCols, dotRows)

	drawTaperedLine(grid, sx(pose.hip.x), sy(pose.hip.y),
		sx(pose.rKnee.x), sy(pose.rKnee.y), ulR, llR, dotCols, dotRows)
	drawTaperedLine(grid, sx(pose.rKnee.x), sy(pose.rKnee.y),
		sx(pose.rFoot.x), sy(pose.rFoot.y), llR, ftR, dotCols, dotRows)

	return gridToBrailleMultiRow(grid, dotCols, rows)
}
