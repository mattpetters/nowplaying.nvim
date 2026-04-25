package proto

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"sync"
)

// MaxFrameSize caps a single frame to guard against runaway memory.
// Search results with artwork URLs and 50 tracks fit comfortably.
const MaxFrameSize = 1 << 20 // 1 MiB

// Reader decodes newline-delimited JSON frames.
type Reader struct {
	br *bufio.Reader
}

func NewReader(r io.Reader) *Reader {
	br, ok := r.(*bufio.Reader)
	if !ok {
		br = bufio.NewReaderSize(r, 64*1024)
	}
	return &Reader{br: br}
}

// Read returns the next frame. Returns io.EOF when the stream closes
// cleanly between frames.
func (r *Reader) Read() (*Message, error) {
	line, err := readLine(r.br, MaxFrameSize)
	if err != nil {
		return nil, err
	}
	var m Message
	if err := json.Unmarshal(line, &m); err != nil {
		return nil, fmt.Errorf("decode frame: %w", err)
	}
	return &m, nil
}

// Writer encodes newline-delimited JSON frames. Concurrent calls to
// Write are serialized so multiple goroutines can publish notifications
// to the same client without interleaving bytes.
type Writer struct {
	mu sync.Mutex
	w  io.Writer
}

func NewWriter(w io.Writer) *Writer {
	return &Writer{w: w}
}

func (w *Writer) Write(m *Message) error {
	if m.JSONRPC == "" {
		m.JSONRPC = "2.0"
	}
	buf, err := json.Marshal(m)
	if err != nil {
		return fmt.Errorf("encode frame: %w", err)
	}
	if len(buf)+1 > MaxFrameSize {
		return fmt.Errorf("frame too large: %d bytes", len(buf))
	}
	buf = append(buf, '\n')
	w.mu.Lock()
	defer w.mu.Unlock()
	_, err = w.w.Write(buf)
	return err
}

// readLine reads up to a '\n' delimiter, enforcing maxLen. The trailing
// newline is stripped. Lines may be split across buffer fills.
func readLine(br *bufio.Reader, maxLen int) ([]byte, error) {
	var out []byte
	for {
		chunk, err := br.ReadSlice('\n')
		if err == nil {
			if len(out)+len(chunk) > maxLen {
				return nil, fmt.Errorf("frame exceeds %d bytes", maxLen)
			}
			if len(out) == 0 {
				return trimNewline(chunk), nil
			}
			out = append(out, chunk...)
			return trimNewline(out), nil
		}
		if err == bufio.ErrBufferFull {
			out = append(out, chunk...)
			if len(out) > maxLen {
				return nil, fmt.Errorf("frame exceeds %d bytes", maxLen)
			}
			continue
		}
		// EOF or other error.
		if len(out)+len(chunk) > 0 {
			out = append(out, chunk...)
			if err == io.EOF {
				return nil, io.ErrUnexpectedEOF
			}
		}
		return nil, err
	}
}

func trimNewline(b []byte) []byte {
	if n := len(b); n > 0 && b[n-1] == '\n' {
		b = b[:n-1]
		if n := len(b); n > 0 && b[n-1] == '\r' {
			b = b[:n-1]
		}
	}
	// Copy because bufio reuses the slice.
	out := make([]byte, len(b))
	copy(out, b)
	return out
}
