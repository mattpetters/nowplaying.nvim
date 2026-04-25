// Package proto defines the JSON-RPC 2.0 wire types spoken between
// nowplayingd and its clients (the TUI and the Neovim plugin).
//
// Framing is newline-delimited JSON: each message is a single JSON
// object terminated by '\n'. This keeps the Lua client trivial — it
// can use a line-buffered read loop with vim.uv pipes.
package proto

import (
	"encoding/json"
	"errors"
	"fmt"
)

const Version = "nowplaying/v1"

// Message is the union of every frame on the wire. Exactly one of
// Method (request or notification) or Result/Error (response) is set.
type Message struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      *json.RawMessage `json:"id,omitempty"`
	Method  string          `json:"method,omitempty"`
	Params  json.RawMessage `json:"params,omitempty"`
	Result  json.RawMessage `json:"result,omitempty"`
	Error   *Error          `json:"error,omitempty"`
}

type Error struct {
	Code    int             `json:"code"`
	Message string          `json:"message"`
	Data    json.RawMessage `json:"data,omitempty"`
}

func (e *Error) Error() string {
	return fmt.Sprintf("rpc error %d: %s", e.Code, e.Message)
}

// Standard JSON-RPC error codes plus our own.
const (
	CodeParseError     = -32700
	CodeInvalidRequest = -32600
	CodeMethodNotFound = -32601
	CodeInvalidParams  = -32602
	CodeInternalError  = -32603

	// Application codes start at -32000 (JSON-RPC reserves -32099..-32000).
	CodeProviderError = -32000
	CodeAuthRequired  = -32001
	CodeNotConnected  = -32002
)

// Method names. Centralized so typos surface at compile time.
const (
	MethodStateGet         = "state.get"
	MethodStateSubscribe   = "state.subscribe"
	MethodTransportPlay    = "transport.play"
	MethodTransportPause   = "transport.pause"
	MethodTransportToggle  = "transport.toggle"
	MethodTransportNext    = "transport.next"
	MethodTransportPrev    = "transport.prev"
	MethodTransportSeek    = "transport.seek"
	MethodTransportVolume  = "transport.volume"
	MethodProviderList     = "provider.list"
	MethodProviderSet      = "provider.set"
	MethodSearchQuery      = "search.query"
	MethodSearchPlay       = "search.play"
	MethodPlaylistList     = "playlist.list"
	MethodPlaylistTracks   = "playlist.tracks"
	MethodAuthStart        = "auth.start"
	MethodAuthStatus       = "auth.status"

	NotifyStateChanged  = "state.changed"
	NotifyTrackChanged  = "track.changed"
	NotifyProgressTick  = "progress.tick"
	NotifyAuthRequired  = "auth.required"
	NotifyError         = "error"
)

// PlayerState is the canonical state served to clients.
type PlayerState struct {
	Provider   string  `json:"provider"`
	Status     Status  `json:"status"`
	Track      *Track  `json:"track,omitempty"`
	Volume     int     `json:"volume"`
	PositionMS int64   `json:"position_ms"`
	UpdatedAt  int64   `json:"updated_at"` // unix millis when state was sampled
}

type Status string

const (
	StatusUnknown Status = ""
	StatusPlaying Status = "playing"
	StatusPaused  Status = "paused"
	StatusStopped Status = "stopped"
)

type Track struct {
	ID         string `json:"id,omitempty"`
	Title      string `json:"title"`
	Artist     string `json:"artist"`
	Album      string `json:"album,omitempty"`
	DurationMS int64  `json:"duration_ms"`
	ArtworkURL string `json:"artwork_url,omitempty"`
	// ArtworkPath is set by the daemon once the artwork is cached locally.
	ArtworkPath string `json:"artwork_path,omitempty"`
	URI         string `json:"uri,omitempty"` // provider-specific (spotify:track:..., music://...)
}

// Param payloads.

type SeekParams struct {
	MS int64 `json:"ms"`
}

type VolumeParams struct {
	Level int `json:"level"` // 0..100
}

type ProviderSetParams struct {
	Provider string `json:"provider"`
}

type SearchQueryParams struct {
	Q     string `json:"q"`
	Type  string `json:"type"`           // "track" | "album" | "playlist"
	Limit int    `json:"limit,omitempty"`
}

type SearchPlayParams struct {
	URI     string `json:"uri"`
	Context string `json:"context,omitempty"` // optional album/playlist URI for "play in context"
}

type SearchResult struct {
	Tracks    []Track    `json:"tracks,omitempty"`
	Albums    []Album    `json:"albums,omitempty"`
	Playlists []Playlist `json:"playlists,omitempty"`
}

type Album struct {
	URI    string `json:"uri"`
	Name   string `json:"name"`
	Artist string `json:"artist"`
	Art    string `json:"artwork_url,omitempty"`
}

type Playlist struct {
	URI         string `json:"uri"`
	Name        string `json:"name"`
	Description string `json:"description,omitempty"`
	Owner       string `json:"owner,omitempty"`
	Art         string `json:"artwork_url,omitempty"`
}

type ProviderInfo struct {
	Name      string `json:"name"`
	Active    bool   `json:"active"`
	Available bool   `json:"available"`
}

type AuthStartResult struct {
	URL  string `json:"url"`
	Code string `json:"code,omitempty"` // optional human-displayable code
}

type AuthStatus struct {
	Connected   bool   `json:"connected"`
	Provider    string `json:"provider"`
	ExpiresAt   int64  `json:"expires_at,omitempty"`
	Scopes      []string `json:"scopes,omitempty"`
}

// Notification payloads.

type TrackChanged struct {
	Prev    *Track `json:"prev,omitempty"`
	Current *Track `json:"current,omitempty"`
}

type ProgressTick struct {
	PositionMS int64 `json:"position_ms"`
	DurationMS int64 `json:"duration_ms"`
	TS         int64 `json:"ts"` // unix millis
}

type AuthRequired struct {
	Provider string `json:"provider"`
}

type ErrorNotification struct {
	Provider string `json:"provider,omitempty"`
	Code     int    `json:"code"`
	Message  string `json:"message"`
}

// NewRequest builds a JSON-RPC request with the given id.
func NewRequest(id any, method string, params any) (*Message, error) {
	rawID, err := json.Marshal(id)
	if err != nil {
		return nil, fmt.Errorf("encode id: %w", err)
	}
	raw := json.RawMessage(rawID)
	m := &Message{JSONRPC: "2.0", ID: &raw, Method: method}
	if params != nil {
		p, err := json.Marshal(params)
		if err != nil {
			return nil, fmt.Errorf("encode params: %w", err)
		}
		m.Params = p
	}
	return m, nil
}

// NewNotification builds a JSON-RPC notification (no id).
func NewNotification(method string, params any) (*Message, error) {
	m := &Message{JSONRPC: "2.0", Method: method}
	if params != nil {
		p, err := json.Marshal(params)
		if err != nil {
			return nil, fmt.Errorf("encode params: %w", err)
		}
		m.Params = p
	}
	return m, nil
}

// NewResponse builds a successful response.
func NewResponse(id json.RawMessage, result any) (*Message, error) {
	m := &Message{JSONRPC: "2.0", ID: &id}
	if result != nil {
		r, err := json.Marshal(result)
		if err != nil {
			return nil, fmt.Errorf("encode result: %w", err)
		}
		m.Result = r
	} else {
		m.Result = json.RawMessage(`null`)
	}
	return m, nil
}

// NewErrorResponse builds an error response.
func NewErrorResponse(id json.RawMessage, code int, message string, data any) (*Message, error) {
	e := &Error{Code: code, Message: message}
	if data != nil {
		d, err := json.Marshal(data)
		if err != nil {
			return nil, fmt.Errorf("encode error data: %w", err)
		}
		e.Data = d
	}
	return &Message{JSONRPC: "2.0", ID: &id, Error: e}, nil
}

// IsRequest reports whether m is a request (has id and method).
func (m *Message) IsRequest() bool { return m.ID != nil && m.Method != "" }

// IsNotification reports whether m is a notification (method, no id).
func (m *Message) IsNotification() bool { return m.ID == nil && m.Method != "" }

// IsResponse reports whether m is a response (has id, no method).
func (m *Message) IsResponse() bool { return m.ID != nil && m.Method == "" }

// Validate checks invariants. Used by the server before dispatch.
func (m *Message) Validate() error {
	if m.JSONRPC != "2.0" {
		return errors.New("missing or invalid jsonrpc version")
	}
	if m.Method == "" && m.ID == nil {
		return errors.New("frame has neither method nor id")
	}
	if m.Result != nil && m.Error != nil {
		return errors.New("response has both result and error")
	}
	return nil
}
