package tui

import "math"

const (
	particleMaxLife = 30
	particleGrav    = 0.15
	maxParticles    = 300
)

func (v *visualizer) tickParticles(playing bool) {
	if !playing {
		// Fade out existing particles.
		alive := v.particles[:0]
		for i := range v.particles {
			p := &v.particles[i]
			p.life--
			p.y += p.vy
			p.vy += particleGrav
			p.bright *= 0.92
			if p.life > 0 && p.y < float64(v.vizRows*4) {
				alive = append(alive, *p)
			}
		}
		v.particles = alive
		return
	}

	// Spawn new particles based on band energy.
	spawnBands := min(v.bars, 16)
	for i := range spawnBands {
		energy := v.heights[i*v.bars/spawnBands] / maxHeight
		if energy < 0.15 {
			continue
		}
		count := int(energy * 3)
		for range count {
			if len(v.particles) >= maxParticles {
				break
			}
			band := float64(i) / float64(spawnBands)
			x := band*float64(v.bars*2-2) + prand(v.frame, i*100+len(v.particles))*4 - 2
			v.particles = append(v.particles, particle{
				x:      x,
				y:      0,
				vy:     0.5 + energy*2 + prand(v.frame, i*200+len(v.particles)),
				life:   int(float64(particleMaxLife) * (0.5 + energy*0.5)),
				bright: energy,
			})
		}
	}

	// Update existing particles.
	alive := v.particles[:0]
	for i := range v.particles {
		p := &v.particles[i]
		p.life--
		p.y += p.vy
		p.vy += particleGrav * 0.5
		p.bright *= 0.95
		if p.life > 0 && p.y < float64(v.vizRows*4) && p.y >= 0 {
			alive = append(alive, *p)
		}
	}
	v.particles = alive
}

func (v *visualizer) renderParticles() string {
	rows := v.vizRows
	dotRows := rows * 4
	dotCols := v.bars * 2

	grid := make([][]bool, dotRows)
	for r := range grid {
		grid[r] = make([]bool, dotCols)
	}

	for _, p := range v.particles {
		ix := int(math.Round(p.x))
		iy := int(math.Round(p.y))
		if ix >= 0 && ix < dotCols && iy >= 0 && iy < dotRows && p.bright > 0.1 {
			grid[iy][ix] = true
			// Brighter particles get a trail.
			if p.bright > 0.4 && iy > 0 {
				grid[iy-1][ix] = true
			}
		}
	}

	return gridToBrailleMultiRow(grid, dotCols, rows)
}
