package tui

import "strings"

// renderErotic is intentionally hand-authored text art, not the procedural
// stick/silhouette renderer used by dancer/ipod/007. The reference is a
// horizontal lounging pin-up/anime muse, so this mode swaps dense Unicode
// frames that read as an illustration instead of a shadow puppet.
func (v *visualizer) renderErotic() string {
	frames := loungeMuseFrames
	step := 18
	if v.playing {
		frames = playMuseFrames
		step = 6
	}
	if len(frames) == 0 {
		return ""
	}
	idx := (v.frame / step) % len(frames)
	return fitTextFrame(frames[idx], v.bars, v.vizRows)
}

var loungeMuseFrames = [][]string{
	{
		"                              ⣀⣤⣴⣶⣿⣿⣶⣄                         ",
		"                         ⣠⣾⣿⣿⣿⣿⣿⣿⣿⣿⣦    z z             ",
		"                     ⣀⡴⠋⠁  ⣀⣀⡀  ⠙⢿⣿⣿⣷⡄                 ",
		"             ⣀⡤⠖⠋     ⡴⠋  ⠙⢦   ⠈⢿⣿⣿⣆                ",
		"        ⣠⠞⠁      ⣀⠴⠋        ⠙⠦⣀  ⠻⣿⣿⡄              ",
		"     ⡴⠋       ⡴⠁   ⢀⣤⣤⣄  ⣠⣤⣤⡀ ⠈⢿⣿⡇              ",
		"   ⡼⠁      ⡼⠁    ⢸⣿⣿⣿⠇⠸⣿⣿⣿⡇   ⢻⡇               ",
		"  ⡜       ⢰⠃       ⠉⠛⠋    ⠙⠛⠉     ⢳                ",
		" ⢰⠁        ⢣          ⣀⣀⣀⣀⣀        ⡜                ",
		" ⡎          ⠙⠲⠤⠤⠖⠚⠉  bikini ⠉⠓⠦⠴⠋                 ",
		"⢸     ⣀⠤⠒⠒⠒⠢⣄       ⣀⣀⣀⣀⣀                         ",
		"⠘⣆⣠⠞⠁          ⠉⠑⠒⠊⠉        ⠉⠓⠦⣀                   ",
		"  ⠉       ⣀⣀⡠⠤⠤⠤⠤⠤⢄⣀             ⠈⠳⣄                ",
		"       ⡠⠚⠉                    ⠉⠒⠤⣀        ⠙⣆              ",
		"    ⡠⠊                               ⠈⠑⠢⣀      ⢸              ",
		"  ⡴⠁        lazy lounge / breathing softly        ⠙⠢⣄⡼              ",
		" ⠘⠦⣀                                                   ⣀⡴⠃              ",
		"     ⠉⠑⠒⠤⠤⣀⣀                         ⣀⣀⠤⠒⠉                 ",
	},
	{
		"                            ⣀⣤⣶⣿⣿⣿⣶⣄                           ",
		"                       ⢀⣴⣿⣿⣿⣿⣿⣿⣿⣿⣧      stretch...       ",
		"                   ⣀⡴⠋⠉  ⣀⣀⡀   ⠙⣿⣷⡀                   ",
		"         ⢀⣀⠴⠊        ⡴⠋  ⠙⢦    ⢻⣿⣇                  ",
		"    ⢀⡴⠋          ⣠⠞          ⠳⣄  ⠹⣿⡄                 ",
		"  ⣠⠋          ⣠⠞     ⢀⣶⣶⣄  ⣠⣶⣶⡀ ⢹⡇                 ",
		" ⢰⠃         ⢰⠃       ⢸⣿⣿⣿⠇⠸⣿⣿⣿⡇ ⢸                  ",
		" ⡎           ⢣         ⠈⠉⠁    ⠈⠉⠁  ⡼                  ",
		"⢰⠁             ⠙⠦⣀         ⣀⣀⣀⣠⠞                   ",
		"⢸       ⣀⠤⠒⠒⠒⠒⠢⣄   ⠉⠒⠒⠉                          ",
		"⠘⣆⣀⠴⠋              ⠉⠢⣀      ⣀⣀⣀⣀                       ",
		"  ⠉                 ⠈⠑⠒⠒⠉       ⠉⠓⠤⣀                 ",
		"       ⣀⣀⠤⠤⠒⠒⠒⠒⠒⠒⠢⢄⣀              ⠙⠢⣀              ",
		"  ⢀⠞⠁                         ⠉⠒⠤⣀          ⠙⣆            ",
		" ⢰⠃                                  ⠈⠑⠢⣀       ⢸            ",
		"  ⠳⣄       one arm tucked behind her hair             ⠙⠢⣄⡼            ",
		"     ⠙⠲⠤⣀                                             ⣀⡴⠋            ",
		"          ⠉⠒⠤⣀⣀                           ⣀⣀⠤⠒⠉               ",
	},
	{
		"                              ⣀⣤⣴⣶⣿⣿⣶⣄                         ",
		"                         ⣠⣾⣿⣿⣿⣿⣿⣿⣿⣿⣦                    ",
		"                      ⣠⠞⠁   ⣀⡀    ⠙⢿⣿⣆      hm?          ",
		"                ⣠⠔⠁      ⡴⠋⠙⢦       ⢻⣿⡄                ",
		"          ⣀⠔⠁        ⡴⠁     ⠳⡀      ⢿⣧                ",
		"     ⢀⠞⠁          ⡼    ⢀⣤⣤⡀ ⢀⣤⣤⡀  ⢻                ",
		"   ⢀⠏             ⡇    ⢿⣿⣿⡿ ⢿⣿⣿⡿  ⡜                ",
		"   ⡞              ⠘⣄     ⠉⠉    ⠉⠉  ⣠⠋                ",
		"  ⢰⠁                ⠈⠓⠤⣀⣀      ⣀⡠⠞⠁                  ",
		"  ⡜      ⣀⠤⠖⠒⠒⠒⠤⣀       ⠉⠉                         ",
		" ⢰⠁  ⣠⠞⠁             ⠙⠢⣀       ⣀⣀⣀                    ",
		" ⠈⠓⠚⠁                    ⠈⠑⠒⠒⠉     ⠉⠒⠤⣀              ",
		"        ⣀⠤⠒⠒⠒⠢⠤⣀                         ⠙⠢⡀            ",
		"    ⣠⠞⠁               ⠉⠒⠤⣀                    ⠙⣄          ",
		"   ⡜                         ⠈⠑⠢⣀                 ⢸          ",
		"   ⠳⣄       idle pose: side lounge, knees stacked       ⠙⠢⣀⡴⠃          ",
		"      ⠙⠲⠤⣀                                         ⣀⠤⠚⠁            ",
		"           ⠉⠒⠤⣀⣀                         ⣀⣀⠤⠒⠉                 ",
	},
}

var playMuseFrames = [][]string{
	{
		"                         ⣀⣤⣶⣿⣿⣿⣿⣿⣶⣄        haha ♪          ",
		"                    ⢀⣴⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣦                  ",
		"                ⣀⡴⠋⠁  ⣀⣀⣀      ⠙⢿⣿⣿⣆                ",
		"        ⣀⡤⠖⠋       ⡴⠋   ⠙⢦       ⢻⣿⣿⡄              ",
		"   ⣠⠞⠁          ⣠⠞         ⠙⢦      ⢿⣿⡇              ",
		" ⢠⠏           ⣠⠞    ⣀⣶⣶⣄  ⣠⣶⣶⣄   ⢸⣿⠃              ",
		"⢀⡏          ⢠⠏      ⣿⣿⣿⡿  ⢿⣿⣿⣿    ⡼                ",
		"⢸           ⢸        ⠈⠙⠋    ⠙⠛⠁  ⣠⠞                 ",
		"⠸⣄          ⠘⣄          ⣀⣀⣀⡠⠤⠚⠁                  ",
		"  ⠙⠦⣀         ⠈⠓⠦⠤⠖⠚⠉     top adjust                   ",
		"       ⠉⠓⠤⣀       ⣀⠤⠒⠒⠢⣄                            ",
		"              ⠈⠉⠉⠉⠁          ⠙⠢⣀                         ",
		"       ⣀⠤⠒⠒⠒⠢⠤⣀              ⠈⠙⠦⣀                    ",
		"   ⢀⠞⠁               ⠙⠢⣀              ⠙⠢⣀                ",
		"  ⢰⠃       beat sway: shoulders / hips / hair        ⠙⣆              ",
		"   ⠳⣄                                             ⣀⡴⠃              ",
		"      ⠉⠒⠤⣀⣀                           ⣀⣀⠤⠒⠉                 ",
		"             ⠉⠒⠤⣀⣀             ⣀⣀⠤⠒⠉                       ",
	},
	{
		"                             ⣀⣤⣶⣿⣿⣿⣿⣶⣄                       ",
		"                        ⣠⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣦     hehe           ",
		"                   ⣀⡴⠋⠁    ⣀⣀⡀    ⠙⢿⣿⣷⡄             ",
		"             ⣠⠔⠋         ⡴⠋  ⠙⢦       ⢻⣿⣇             ",
		"       ⣀⠞⠁          ⣠⠞        ⠙⣆       ⢿⣿             ",
		"   ⢀⡞⠁           ⣠⠞    ⢀⣤⣤⣄ ⣠⣤⣤⡀   ⢸⡟             ",
		"  ⢠⠇            ⢰⠃      ⢿⣿⣿⡿ ⢿⣿⣿⡿   ⡼              ",
		"  ⡜              ⠘⣄       ⠉⠉    ⠉⠉  ⣠⠋              ",
		" ⢰⠁                ⠈⠓⠦⣀⣀       ⣀⠤⠚⠁                ",
		" ⢸       ⣀⠤⠒⠒⠒⠢⢄⡀      ⠉⠉                            ",
		" ⠘⣆⣀⠴⠋              ⠈⠓⠤⣀       ⣀⠤⠒⠒⠢⣄              ",
		"   ⠉                         ⠉⠒⠒⠉          ⠙⠢⣀           ",
		"         ⣀⡠⠤⠤⣀                              ⠙⠢⣀       ",
		"     ⡠⠊          ⠙⠢⣀                             ⠙⣆     ",
		"    ⡎      stretch frame: long horizontal line, leg opens     ⢸     ",
		"     ⠳⣄                                               ⣀⡴⠃     ",
		"        ⠉⠒⠤⣀⣀                             ⣀⣀⠤⠒⠉        ",
		"              ⠉⠒⠤⣀⣀               ⣀⣀⠤⠒⠉               ",
	},
	{
		"                      ⣀⣤⣴⣶⣿⣿⣿⣿⣿⣶⣤⣀                    ",
		"                 ⢀⣴⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣦                  ",
		"             ⣀⡴⠋⠁    ⣀⣀⣀       ⠙⢿⣿⣷⡀   ♪             ",
		"      ⣀⡤⠖⠋        ⡴⠋   ⠙⢦        ⢻⣿⣧               ",
		" ⢀⡴⠋           ⣠⠞         ⠙⢦       ⢿⣿               ",
		"⣠⠋            ⢀⡞     ⣠⣶⣶⣄  ⣠⣶⣶⣄   ⡿               ",
		"⡇              ⢸      ⠸⣿⣿⣿⡇ ⢸⣿⣿⣿⠇  ⡇               ",
		"⢣              ⠘⣄       ⠙⠛⠋   ⠙⠛⠋  ⣠⠃               ",
		" ⠳⣄              ⠙⠢⣀       ⣀⣀⡠⠤⠚⠁                ",
		"   ⠙⠲⣄             ⠈⠉⠉⠉⠉                              ",
		"       ⠈⠙⠒⠤⣀       ⣀⠤⠒⠒⠢⢄⣀                         ",
		"              ⠉⠓⠒⠒⠚⠁             ⠙⠢⣀                     ",
		"      ⣀⠤⠒⠒⠤⣀                         ⠙⠢⣀                 ",
		"  ⢀⠞⠁            ⠙⠢⣀                         ⠙⢦               ",
		" ⢰⠃        playful roll frame, hair and hips follow beat      ⢸               ",
		"  ⠳⣄                                                   ⣀⡴⠃               ",
		"     ⠉⠒⠤⣀⣀                               ⣀⣀⠤⠒⠉                  ",
		"           ⠉⠒⠤⣀⣀                   ⣀⣀⠤⠒⠉                       ",
	},
	{
		"                            ⣀⣤⣶⣿⣿⣿⣿⣶⣄                       ",
		"                       ⣠⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣧     ahaha ♪        ",
		"                  ⣀⡴⠋⠁  ⣀⣀⣀      ⠙⢿⣿⣿⡄              ",
		"            ⣠⠔⠋       ⡴⠋   ⠙⢦       ⢻⣿⣇              ",
		"      ⣀⠞⠁         ⣠⠞         ⠙⢦      ⢿⣿              ",
		"  ⢀⡞⠁          ⣠⠞    ⢀⣤⣤⣄   ⣠⣤⣤⡀  ⢸⡟              ",
		" ⢠⠇           ⢰⠃      ⢿⣿⣿⡿   ⢿⣿⣿⡿  ⡼               ",
		" ⡜             ⠘⣄       ⠉⠉      ⠉⠉  ⣠⠋               ",
		"⢰⠁               ⠈⠓⠤⣀⣀        ⣀⠤⠚⠁                 ",
		"⢸       ⣀⠤⠒⠒⠒⠢⣄      ⠉⠉                              ",
		"⠘⣆⣀⠴⠋              ⠉⠢⣀        ⣀⣀⣀                     ",
		"  ⠉                         ⠉⠒⠒⠉       ⠉⠓⠤⣀                ",
		"       ⣀⠤⠒⠒⠒⠢⠤⣀                           ⠙⠢⣀            ",
		"   ⣠⠞⠁               ⠙⠢⣀            legs sweep wider   ⠙⣆          ",
		"  ⡜                                      with the downbeat  ⢸          ",
		"  ⠳⣄                                                   ⣀⡴⠃          ",
		"     ⠙⠲⠤⣀                                     ⣀⠤⠚⠁             ",
		"          ⠉⠒⠤⣀⣀                       ⣀⣀⠤⠒⠉                  ",
	},
}

func fitTextFrame(frame []string, width, rows int) string {
	if width < 1 {
		width = 1
	}
	if rows < 1 {
		rows = 1
	}

	out := make([]string, rows)
	startLine := 0
	if len(frame) > rows {
		startLine = (len(frame) - rows) / 2
	}
	for i := range rows {
		line := ""
		if startLine+i < len(frame) {
			line = frame[startLine+i]
		}
		out[i] = fitTextLine(line, width)
	}
	return strings.Join(out, "\n")
}

func fitTextLine(line string, width int) string {
	r := []rune(line)
	if len(r) > width {
		start := (len(r) - width) / 2
		return string(r[start : start+width])
	}
	if len(r) < width {
		left := (width - len(r)) / 2
		right := width - len(r) - left
		return strings.Repeat(" ", left) + line + strings.Repeat(" ", right)
	}
	return line
}
