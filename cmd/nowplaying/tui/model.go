// Package tui hosts the Bubble Tea model for the standalone TUI.
package tui

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/mpetters/nowplaying/internal/ipc"
	"github.com/mpetters/nowplaying/internal/proto"
	"github.com/mpetters/nowplaying/internal/theme"
)

// Model is the Bubble Tea model.
type Model struct {
	ctx        context.Context
	socketPath string
	theme      theme.Theme
	styles     theme.Styles

	client *ipc.ConnClient
	conn   bool
	status string
	state  proto.PlayerState

	width, height int
	viz           *visualizer

	searchMode    bool
	searchInput   string
	searchResults []proto.Track
	searchCursor  int

	flash       string
	flashExpiry time.Time
}

// New constructs the initial model.
func New(ctx context.Context, socketPath string, t theme.Theme) Model {
	return Model{
		ctx:        ctx,
		socketPath: socketPath,
		theme:      t,
		styles:     theme.Build(t),
		status:     "connecting...",
		viz:        newVisualizer(20, 2),
	}
}

func (m Model) Init() tea.Cmd {
	return tea.Batch(connectCmd(m.ctx, m.socketPath), tickCmd())
}

// --- messages ---

type connectedMsg struct {
	client *ipc.ConnClient
	state  proto.PlayerState
}
type disconnectedMsg struct{ err error }
type notifMsg struct{ msg *proto.Message }
type tickMsg time.Time
type themeChangedMsg struct{ name string }
type flashMsg struct{ text string }
type likeResultMsg struct{ liked bool }
type searchResultsMsg struct{ tracks []proto.Track }
type authResultMsg struct{ err error }

// --- update ---

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		m.viz.resize(max(m.width-8, 10), m.vizRows())
		return m, nil

	case connectedMsg:
		m.client = msg.client
		m.conn = true
		m.state = msg.state
		m.status = ""
		return m, listenCmd(m.client)

	case disconnectedMsg:
		m.conn = false
		m.client = nil
		m.status = fmt.Sprintf("disconnected: %v — retrying...", msg.err)
		return m, tea.Tick(2*time.Second, func(time.Time) tea.Msg {
			return reconnect{}
		})

	case reconnect:
		return m, connectCmd(m.ctx, m.socketPath)

	case notifMsg:
		m = applyNotification(m, msg.msg)
		return m, listenCmd(m.client)

	case tickMsg:
		playing := m.state.Status == proto.StatusPlaying && m.state.Track != nil
		if playing {
			m.state.PositionMS += 100
			if m.state.PositionMS > m.state.Track.DurationMS {
				m.state.PositionMS = m.state.Track.DurationMS
			}
		}
		m.viz.tick(playing)
		return m, tickCmd()

	case themeChangedMsg:
		t, err := theme.Get(msg.name)
		if err == nil {
			m.theme = t
			m.styles = theme.Build(t)
		}
		return m, nil

	case flashMsg:
		m.flash = msg.text
		m.flashExpiry = time.Now().Add(3 * time.Second)
		return m, nil

	case likeResultMsg:
		if msg.liked {
			m.flash = "♥ liked"
		} else {
			m.flash = "♡ unliked"
		}
		m.flashExpiry = time.Now().Add(3 * time.Second)
		return m, nil

	case searchResultsMsg:
		if len(msg.tracks) == 0 {
			m.flash = "no results"
			m.flashExpiry = time.Now().Add(3 * time.Second)
			return m, nil
		}
		m.searchResults = msg.tracks
		m.searchCursor = 0
		return m, nil

	case authResultMsg:
		if msg.err != nil {
			m.flash = "auth failed: " + msg.err.Error()
		} else {
			m.flash = "authenticated!"
		}
		m.flashExpiry = time.Now().Add(5 * time.Second)
		return m, nil

	case tea.KeyMsg:
		if len(m.searchResults) > 0 {
			return m.handleResultsKey(msg)
		}
		if m.searchMode {
			return m.handleSearchKey(msg)
		}
		return m.handleKey(msg)
	}
	return m, nil
}

type reconnect struct{}

func (m Model) handleKey(k tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch k.String() {
	case "q", "ctrl+c":
		return m, tea.Quit
	case " ", "space":
		return m, callCmd(m.client, proto.MethodTransportToggle, nil)
	case "n":
		return m, callCmd(m.client, proto.MethodTransportNext, nil)
	case "p":
		return m, callCmd(m.client, proto.MethodTransportPrev, nil)
	case "t":
		next := theme.Next(m.theme.Name)
		return m, func() tea.Msg { return themeChangedMsg{name: next} }
	case "v":
		m.viz.cycleMode()
		return m, nil
	case "/":
		m.searchMode = true
		m.searchInput = ""
		return m, nil
	case "l":
		return m, likeCmd(m.client)
	case "a":
		m.flash = "opening browser for Spotify login..."
		m.flashExpiry = time.Now().Add(120 * time.Second)
		return m, authStartCmd(m.client)
	}
	return m, nil
}

func (m Model) handleSearchKey(k tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch k.Type {
	case tea.KeyEsc:
		m.searchMode = false
		m.searchInput = ""
		return m, nil
	case tea.KeyEnter:
		query := strings.TrimSpace(m.searchInput)
		m.searchMode = false
		m.searchInput = ""
		if query == "" {
			return m, nil
		}
		m.flash = "searching..."
		m.flashExpiry = time.Now().Add(10 * time.Second)
		return m, searchQueryCmd(m.client, query)
	case tea.KeyBackspace:
		runes := []rune(m.searchInput)
		if len(runes) > 0 {
			m.searchInput = string(runes[:len(runes)-1])
		}
		return m, nil
	case tea.KeyCtrlC:
		return m, tea.Quit
	case tea.KeySpace:
		m.searchInput += " "
		return m, nil
	case tea.KeyRunes:
		m.searchInput += string(k.Runes)
		return m, nil
	}
	return m, nil
}

func (m Model) handleResultsKey(k tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch k.String() {
	case "j", "down":
		if m.searchCursor < len(m.searchResults)-1 {
			m.searchCursor++
		}
		return m, nil
	case "k", "up":
		if m.searchCursor > 0 {
			m.searchCursor--
		}
		return m, nil
	case "enter":
		track := m.searchResults[m.searchCursor]
		m.searchResults = nil
		m.flash = "playing: " + track.Title
		m.flashExpiry = time.Now().Add(3 * time.Second)
		return m, playTrackCmd(m.client, track.URI)
	case "esc":
		m.searchResults = nil
		return m, nil
	case "q", "ctrl+c":
		return m, tea.Quit
	}
	return m, nil
}

func applyNotification(m Model, msg *proto.Message) Model {
	switch msg.Method {
	case proto.NotifyStateChanged:
		var s proto.PlayerState
		if err := json.Unmarshal(msg.Params, &s); err == nil {
			m.state = s
		}
	case proto.NotifyProgressTick:
		var p proto.ProgressTick
		if err := json.Unmarshal(msg.Params, &p); err == nil {
			m.state.PositionMS = p.PositionMS
		}
	case proto.NotifyAudioSpectrum:
		var s proto.AudioSpectrum
		if err := json.Unmarshal(msg.Params, &s); err == nil {
			m.viz.feed(s.Bands, s.Samples)
		}
	}
	return m
}

// --- commands ---

func connectCmd(ctx context.Context, path string) tea.Cmd {
	return func() tea.Msg {
		c, err := ipc.DialClient(ctx, path)
		if err != nil {
			return disconnectedMsg{err: err}
		}
		// Subscribe so we receive notifications.
		if _, err := c.Call(ctx, proto.MethodStateSubscribe, nil); err != nil {
			_ = c.Close()
			return disconnectedMsg{err: fmt.Errorf("subscribe: %w", err)}
		}
		// Pull initial state.
		raw, err := c.Call(ctx, proto.MethodStateGet, nil)
		if err != nil {
			_ = c.Close()
			return disconnectedMsg{err: fmt.Errorf("state.get: %w", err)}
		}
		var s proto.PlayerState
		_ = json.Unmarshal(raw, &s)
		return connectedMsg{client: c, state: s}
	}
}

func listenCmd(c *ipc.ConnClient) tea.Cmd {
	if c == nil {
		return nil
	}
	return func() tea.Msg {
		msg, ok := <-c.Notifications()
		if !ok {
			return disconnectedMsg{err: fmt.Errorf("connection closed")}
		}
		return notifMsg{msg: msg}
	}
}

func callCmd(c *ipc.ConnClient, method string, params any) tea.Cmd {
	if c == nil {
		return nil
	}
	return func() tea.Msg {
		_, _ = c.Call(context.Background(), method, params)
		return nil
	}
}

func searchQueryCmd(c *ipc.ConnClient, query string) tea.Cmd {
	if c == nil {
		return nil
	}
	return func() tea.Msg {
		raw, err := c.Call(context.Background(), proto.MethodSearchQuery, proto.SearchQueryParams{
			Q:     query,
			Type:  "track",
			Limit: 10,
		})
		if err != nil {
			return flashMsg{text: "search: " + err.Error()}
		}
		var result proto.SearchResult
		if err := json.Unmarshal(raw, &result); err != nil {
			return flashMsg{text: "search: bad response"}
		}
		return searchResultsMsg{tracks: result.Tracks}
	}
}

func playTrackCmd(c *ipc.ConnClient, uri string) tea.Cmd {
	if c == nil {
		return nil
	}
	return func() tea.Msg {
		_, err := c.Call(context.Background(), proto.MethodSearchPlay, proto.SearchPlayParams{URI: uri})
		if err != nil {
			return flashMsg{text: "play failed"}
		}
		return nil
	}
}

func authStartCmd(c *ipc.ConnClient) tea.Cmd {
	if c == nil {
		return nil
	}
	return func() tea.Msg {
		_, err := c.Call(context.Background(), proto.MethodAuthStart, nil)
		if err != nil {
			return authResultMsg{err: err}
		}
		return authResultMsg{}
	}
}

func likeCmd(c *ipc.ConnClient) tea.Cmd {
	if c == nil {
		return nil
	}
	return func() tea.Msg {
		raw, err := c.Call(context.Background(), proto.MethodLikeToggle, nil)
		if err != nil {
			return flashMsg{text: "like not available"}
		}
		var r proto.LikeToggleResult
		_ = json.Unmarshal(raw, &r)
		return likeResultMsg{liked: r.Liked}
	}
}

func tickCmd() tea.Cmd {
	return tea.Tick(100*time.Millisecond, func(t time.Time) tea.Msg {
		return tickMsg(t)
	})
}

// --- view ---

func (m Model) View() string {
	if !m.conn {
		banner := m.styles.Status.Render("nowplaying") + m.styles.Hint.Render(" — "+m.status)
		hint := m.styles.Hint.Render("press q to quit")
		return lipgloss.JoinVertical(lipgloss.Left, banner, "", hint)
	}

	header := m.styles.Title.Render(headerLine(m.state))
	artist := m.renderArtistAlbum()
	status := m.styles.Status.Render(statusLine(m.state))
	bar := m.renderProgress()

	var middle string
	if len(m.searchResults) > 0 {
		middle = m.renderSearchResults()
	} else {
		middle = m.styles.Progress.Render(m.viz.render())
	}

	var hints string
	if len(m.searchResults) > 0 {
		hints = m.styles.Hint.Render("j/k move · enter play · esc close · q quit")
	} else if m.searchMode {
		hints = m.styles.Title.Render("/") + m.styles.Hint.Render(m.searchInput+"_")
	} else {
		hintParts := fmt.Sprintf("space play/pause · n/p track · / search · l like · a auth · t theme · v viz [%s] · q quit", m.viz.modeName())
		if m.flash != "" && time.Now().Before(m.flashExpiry) {
			hints = m.styles.Title.Render(m.flash) + "  " + m.styles.Hint.Render(hintParts)
		} else {
			hints = m.styles.Hint.Render(hintParts)
		}
	}

	body := lipgloss.JoinVertical(lipgloss.Left,
		header,
		artist,
		"",
		middle,
		bar,
		status,
		"",
		hints,
	)

	bodyWidth := max(m.width-4, 20)
	return m.styles.Border.Width(bodyWidth).Render(body)
}

func (m Model) renderSearchResults() string {
	maxW := max(m.width-12, 30)
	var lines []string
	for i, t := range m.searchResults {
		cursor := "  "
		if i == m.searchCursor {
			cursor = "> "
		}
		dur := fmtMS(t.DurationMS)
		line := fmt.Sprintf("%s%d  %s — %s", cursor, i+1, t.Title, t.Artist)
		// Truncate if too long, leaving room for duration
		durLen := len(dur) + 2
		if len(line) > maxW-durLen {
			line = line[:maxW-durLen-1] + "…"
		}
		padding := maxW - len(line) - len(dur)
		if padding < 1 {
			padding = 1
		}
		line += strings.Repeat(" ", padding) + dur
		if i == m.searchCursor {
			lines = append(lines, m.styles.Title.Render(line))
		} else {
			lines = append(lines, m.styles.Hint.Render(line))
		}
	}
	return strings.Join(lines, "\n")
}

func headerLine(s proto.PlayerState) string {
	if s.Track == nil {
		return "(nothing playing)"
	}
	return s.Track.Title
}

func (m Model) renderArtistAlbum() string {
	if m.state.Track == nil {
		return ""
	}
	artist := m.styles.Artist.Render(m.state.Track.Artist)
	if m.state.Track.Album == "" {
		return artist
	}
	sep := m.styles.Album.Render(" · ")
	album := m.styles.Album.Render(m.state.Track.Album)
	return artist + sep + album
}

func statusLine(s proto.PlayerState) string {
	st := strings.ToUpper(string(s.Status))
	if st == "" {
		st = "UNKNOWN"
	}
	return fmt.Sprintf("[%s]  vol %d  %s", st, s.Volume, s.Provider)
}

func (m Model) renderProgress() string {
	width := max(m.width-8, 10)
	if m.state.Track == nil || m.state.Track.DurationMS == 0 {
		return m.styles.Track.Render(strings.Repeat("─", width))
	}
	pct := float64(m.state.PositionMS) / float64(m.state.Track.DurationMS)
	if pct < 0 {
		pct = 0
	}
	if pct > 1 {
		pct = 1
	}
	filled := int(pct * float64(width))
	bar := m.styles.Progress.Render(strings.Repeat("━", filled)) +
		m.styles.Track.Render(strings.Repeat("─", width-filled))
	timing := fmt.Sprintf(" %s / %s", fmtMS(m.state.PositionMS), fmtMS(m.state.Track.DurationMS))
	return bar + m.styles.Hint.Render(timing)
}

// vizRows computes the number of terminal rows available for the visualizer.
// Chrome: header + artist + blank + progress + status + blank + hints = 7
// Border: top + bottom = 2, plus 0 vertical padding.
const vizChrome = 9

func (m Model) vizRows() int {
	rows := m.height - vizChrome
	if rows < 2 {
		return 2
	}
	return rows
}

func fmtMS(ms int64) string {
	s := ms / 1000
	return fmt.Sprintf("%d:%02d", s/60, s%60)
}
