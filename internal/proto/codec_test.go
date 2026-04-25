package proto

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"strings"
	"sync"
	"testing"
)

func TestCodec_RoundTrip(t *testing.T) {
	var buf bytes.Buffer
	w := NewWriter(&buf)
	r := NewReader(&buf)

	out := []*Message{
		mustReq(t, 1, MethodStateGet, nil),
		mustReq(t, "uuid-2", MethodTransportSeek, SeekParams{MS: 5000}),
		mustNotif(t, NotifyProgressTick, ProgressTick{PositionMS: 1000, DurationMS: 200000, TS: 1700}),
	}
	for _, m := range out {
		if err := w.Write(m); err != nil {
			t.Fatalf("Write: %v", err)
		}
	}
	for i, want := range out {
		got, err := r.Read()
		if err != nil {
			t.Fatalf("Read[%d]: %v", i, err)
		}
		if got.Method != want.Method {
			t.Errorf("[%d] method = %q want %q", i, got.Method, want.Method)
		}
		if (got.ID == nil) != (want.ID == nil) {
			t.Errorf("[%d] id presence mismatch", i)
		}
	}
}

func TestCodec_ReadEOFOnCleanClose(t *testing.T) {
	r := NewReader(&bytes.Buffer{})
	if _, err := r.Read(); !errors.Is(err, io.EOF) {
		t.Fatalf("want EOF, got %v", err)
	}
}

func TestCodec_PartialFrameIsUnexpectedEOF(t *testing.T) {
	// Bytes without a trailing newline.
	r := NewReader(strings.NewReader(`{"jsonrpc":"2.0","method":"x"}`))
	_, err := r.Read()
	if !errors.Is(err, io.ErrUnexpectedEOF) {
		t.Fatalf("want UnexpectedEOF, got %v", err)
	}
}

func TestCodec_RejectsOversizedFrame(t *testing.T) {
	var buf bytes.Buffer
	w := NewWriter(&buf)
	huge := strings.Repeat("a", MaxFrameSize)
	m, _ := NewNotification("oversize", map[string]string{"x": huge})
	if err := w.Write(m); err == nil {
		t.Fatal("expected oversize write to fail")
	}
}

func TestCodec_ReaderRejectsOversizedLine(t *testing.T) {
	// Build a > MaxFrameSize line and feed it as a single chunk.
	huge := bytes.Repeat([]byte("a"), MaxFrameSize+10)
	huge = append(huge, '\n')
	r := NewReader(bytes.NewReader(huge))
	_, err := r.Read()
	if err == nil || !strings.Contains(err.Error(), "exceeds") {
		t.Fatalf("expected size error, got %v", err)
	}
}

func TestCodec_HandlesCRLF(t *testing.T) {
	frame := `{"jsonrpc":"2.0","method":"ping"}` + "\r\n"
	r := NewReader(strings.NewReader(frame))
	m, err := r.Read()
	if err != nil {
		t.Fatalf("Read: %v", err)
	}
	if m.Method != "ping" {
		t.Errorf("method = %q", m.Method)
	}
}

func TestCodec_RejectsMalformedJSON(t *testing.T) {
	r := NewReader(strings.NewReader("not-json\n"))
	if _, err := r.Read(); err == nil {
		t.Fatal("expected decode error")
	}
}

func TestCodec_WriterIsConcurrencySafe(t *testing.T) {
	var buf bytes.Buffer
	w := NewWriter(&buf)
	const n = 50
	var wg sync.WaitGroup
	wg.Add(n)
	for i := range n {
		go func(i int) {
			defer wg.Done()
			m, _ := NewNotification(NotifyProgressTick, ProgressTick{PositionMS: int64(i)})
			_ = w.Write(m)
		}(i)
	}
	wg.Wait()

	r := NewReader(&buf)
	count := 0
	for {
		m, err := r.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			t.Fatalf("Read: %v", err)
		}
		var p ProgressTick
		if err := json.Unmarshal(m.Params, &p); err != nil {
			t.Fatalf("decoded malformed frame: %v (raw=%s)", err, m.Params)
		}
		count++
	}
	if count != n {
		t.Fatalf("got %d frames, want %d", count, n)
	}
}

func mustReq(t *testing.T, id any, method string, params any) *Message {
	t.Helper()
	m, err := NewRequest(id, method, params)
	if err != nil {
		t.Fatalf("NewRequest: %v", err)
	}
	return m
}

func mustNotif(t *testing.T, method string, params any) *Message {
	t.Helper()
	m, err := NewNotification(method, params)
	if err != nil {
		t.Fatalf("NewNotification: %v", err)
	}
	return m
}
