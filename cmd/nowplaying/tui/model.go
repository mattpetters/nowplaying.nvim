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
}

// New constructs the initial model.
func New(ctx context.Context, socketPath string, t theme.Theme) Model {
	return Model{
		ctx:        ctx,
		socketPath: socketPath,
		theme:      t,
		styles:     theme.Build(t),
		status:     "connecting...",
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

// --- update ---

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
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
		// Local progress interpolation between ticks. Keeps the bar moving
		// even though the daemon only ticks 1Hz.
		if m.state.Status == proto.StatusPlaying && m.state.Track != nil {
			m.state.PositionMS += 100
			if m.state.PositionMS > m.state.Track.DurationMS {
				m.state.PositionMS = m.state.Track.DurationMS
			}
		}
		return m, tickCmd()

	case themeChangedMsg:
		t, err := theme.Get(msg.name)
		if err == nil {
			m.theme = t
			m.styles = theme.Build(t)
		}
		return m, nil

	case tea.KeyMsg:
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

func tickCmd() tea.Cmd {
	return tea.Tick(100*time.Millisecond, func(t time.Time) tea.Msg {
		return tickMsg(t)
	})
}

// --- view ---

func (m Model) View() string {
	if !m.conn {
		banner := m.styles.Banner.Render("nowplaying — " + m.status)
		hint := m.styles.Hint.Render("press q to quit")
		return m.styles.Base.Width(m.width).Height(m.height).Render(
			lipgloss.JoinVertical(lipgloss.Left, banner, "", hint),
		)
	}

	header := m.styles.Title.Render(headerLine(m.state))
	artist := m.styles.Artist.Render(artistLine(m.state))
	album := m.styles.Album.Render(albumLine(m.state))
	status := m.styles.Status.Render(statusLine(m.state))
	bar := m.renderProgress()
	hints := m.styles.Hint.Render("space play/pause · n next · p prev · t theme (" + m.theme.Name + ") · q quit")

	body := lipgloss.JoinVertical(lipgloss.Left,
		header,
		artist,
		album,
		"",
		bar,
		status,
		"",
		hints,
	)

	bodyWidth := max(m.width-4, 20)
	box := m.styles.Border.Width(bodyWidth).Render(body)
	return m.styles.Base.Width(m.width).Height(m.height).Render(box)
}

func headerLine(s proto.PlayerState) string {
	if s.Track == nil {
		return "(nothing playing)"
	}
	return s.Track.Title
}

func artistLine(s proto.PlayerState) string {
	if s.Track == nil {
		return ""
	}
	return s.Track.Artist
}

func albumLine(s proto.PlayerState) string {
	if s.Track == nil || s.Track.Album == "" {
		return ""
	}
	return s.Track.Album
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

func fmtMS(ms int64) string {
	s := ms / 1000
	return fmt.Sprintf("%d:%02d", s/60, s%60)
}
