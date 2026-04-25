package proto

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestNewRequest_RoundTrip(t *testing.T) {
	req, err := NewRequest(7, MethodTransportSeek, SeekParams{MS: 12345})
	if err != nil {
		t.Fatalf("NewRequest: %v", err)
	}
	if !req.IsRequest() {
		t.Fatal("expected IsRequest")
	}
	if req.Method != MethodTransportSeek {
		t.Errorf("method = %q", req.Method)
	}
	var got SeekParams
	if err := json.Unmarshal(req.Params, &got); err != nil {
		t.Fatalf("unmarshal params: %v", err)
	}
	if got.MS != 12345 {
		t.Errorf("ms = %d", got.MS)
	}
	// id round-trips as a json number.
	var id int
	if err := json.Unmarshal(*req.ID, &id); err != nil {
		t.Fatalf("unmarshal id: %v", err)
	}
	if id != 7 {
		t.Errorf("id = %d", id)
	}
}

func TestNewNotification_HasNoID(t *testing.T) {
	n, err := NewNotification(NotifyTrackChanged, TrackChanged{Current: &Track{Title: "Hey"}})
	if err != nil {
		t.Fatalf("NewNotification: %v", err)
	}
	if n.ID != nil {
		t.Fatal("notifications must not have an id")
	}
	if !n.IsNotification() {
		t.Fatal("expected IsNotification")
	}
}

func TestNewResponse_NullResult(t *testing.T) {
	id := json.RawMessage(`"abc"`)
	r, err := NewResponse(id, nil)
	if err != nil {
		t.Fatalf("NewResponse: %v", err)
	}
	if !r.IsResponse() {
		t.Fatal("expected IsResponse")
	}
	if string(r.Result) != "null" {
		t.Errorf("result = %s", r.Result)
	}
}

func TestNewErrorResponse(t *testing.T) {
	id := json.RawMessage(`42`)
	r, err := NewErrorResponse(id, CodeInvalidParams, "bad", map[string]any{"field": "ms"})
	if err != nil {
		t.Fatalf("NewErrorResponse: %v", err)
	}
	if r.Error == nil || r.Error.Code != CodeInvalidParams {
		t.Fatalf("error: %+v", r.Error)
	}
	if got := r.Error.Error(); !strings.Contains(got, "bad") {
		t.Errorf("error string: %s", got)
	}
}

func TestValidate(t *testing.T) {
	cases := []struct {
		name string
		m    Message
		want bool
	}{
		{"missing version", Message{Method: "x"}, false},
		{"empty frame", Message{JSONRPC: "2.0"}, false},
		{"both result and error", Message{
			JSONRPC: "2.0",
			ID:      rawID(1),
			Result:  json.RawMessage(`{}`),
			Error:   &Error{Code: 1, Message: "x"},
		}, false},
		{"valid request", Message{JSONRPC: "2.0", ID: rawID(1), Method: "x"}, true},
		{"valid notification", Message{JSONRPC: "2.0", Method: "x"}, true},
		{"valid response", Message{JSONRPC: "2.0", ID: rawID(1), Result: json.RawMessage(`null`)}, true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := tc.m.Validate()
			if (err == nil) != tc.want {
				t.Errorf("Validate err = %v, want ok=%v", err, tc.want)
			}
		})
	}
}

func TestPlayerState_JSON(t *testing.T) {
	ps := PlayerState{
		Provider: "spotify",
		Status:   StatusPlaying,
		Track: &Track{
			Title:      "Trampled Underfoot",
			Artist:     "Led Zeppelin",
			DurationMS: 336000,
			ArtworkURL: "https://example/x.jpg",
		},
		Volume:     65,
		PositionMS: 12000,
		UpdatedAt:  1700000000000,
	}
	buf, err := json.Marshal(ps)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	var got PlayerState
	if err := json.Unmarshal(buf, &got); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if got.Track.Title != ps.Track.Title || got.Status != StatusPlaying {
		t.Errorf("got %+v", got)
	}
}

func rawID(n int) *json.RawMessage {
	b, _ := json.Marshal(n)
	r := json.RawMessage(b)
	return &r
}
