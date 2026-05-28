package asciiart

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
)

// ─── Eikon Format ─────────────────────────────────────────────────────────

type eikonMeta struct {
	T    string `json:"t"`
	V    int    `json:"v"`
	ID   string `json:"id"`
	Grid struct {
		W int `json:"w"`
		H int `json:"h"`
	} `json:"grid"`
}

type eikonStates struct {
	T        string   `json:"t"`
	States   []string `json:"states"`
	LoopFrom int      `json:"loopFrom"`
}

type eikonFrames struct {
	T       string       `json:"t"`
	Total   int          `json:"total"`
	Ranges  []eikonRange `json:"ranges"`
}

type eikonRange struct {
	S string `json:"s"`
	B int    `json:"b"`
	C int    `json:"c"`
}

type eikonFrameLine struct {
	T string   `json:"t"`
	I int      `json:"i"`
	G []string `json:"g"`
}

// EncodeEikon serializes frames to the NDJSON eikon format.
func EncodeEikon(frames []Frame, artistID string) ([]byte, error) {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)

	if len(frames) == 0 {
		return nil, fmt.Errorf("asciiart: no frames to encode")
	}

	gridW := 0
	gridH := len(frames[0].Grid)
	if gridH > 0 {
		gridW = len(frames[0].Grid[0])
	}

	meta := eikonMeta{
		T:  "eikon",
		V:  1,
		ID: artistID,
	}
	meta.Grid.W = gridW
	meta.Grid.H = gridH
	if err := enc.Encode(meta); err != nil {
		return nil, fmt.Errorf("encode meta: %w", err)
	}

	states := eikonStates{
		T:        "states",
		States:   []string{"idle"},
		LoopFrom: 0,
	}
	if err := enc.Encode(states); err != nil {
		return nil, fmt.Errorf("encode states: %w", err)
	}

	fm := eikonFrames{
		T:     "frames",
		Total: len(frames),
		Ranges: []eikonRange{{
			S: "idle",
			B: 0,
			C: len(frames),
		}},
	}
	if err := enc.Encode(fm); err != nil {
		return nil, fmt.Errorf("encode frames: %w", err)
	}

	for i, f := range frames {
		fl := eikonFrameLine{
			T: "frame",
			I: i,
			G: f.Grid,
		}
		if err := enc.Encode(fl); err != nil {
			return nil, fmt.Errorf("encode frame %d: %w", i, err)
		}
	}

	return buf.Bytes(), nil
}

// DecodeEikon deserializes an eikon file into frames.
func DecodeEikon(r io.Reader) ([]Frame, string, error) {
	data, err := io.ReadAll(r)
	if err != nil {
		return nil, "", fmt.Errorf("read eikon: %w", err)
	}
	return DecodeEikonLines(data)
}

// DecodeEikonLines decodes eikon data from a byte slice containing NDJSON.
func DecodeEikonLines(data []byte) ([]Frame, string, error) {
	scanner := bufio.NewScanner(bytes.NewReader(data))
	scanner.Buffer(make([]byte, 1024*1024), 1024*1024)

	var frames []Frame
	var artistID string

	for scanner.Scan() {
		line := bytes.TrimSpace(scanner.Bytes())
		if len(line) == 0 {
			continue
		}

		var typeHolder struct {
			T string `json:"t"`
		}
		if err := json.Unmarshal(line, &typeHolder); err != nil {
			continue
		}

		switch typeHolder.T {
		case "eikon":
			var meta eikonMeta
			if err := json.Unmarshal(line, &meta); err == nil {
				artistID = meta.ID
			}
		case "frame":
			var fl eikonFrameLine
			if err := json.Unmarshal(line, &fl); err != nil {
				continue
			}
			frames = append(frames, Frame{
				Grid:  fl.G,
				Delay: 125,
				Info:  FrameInfo{Index: fl.I},
			})
		}
	}

	if err := scanner.Err(); err != nil {
		return nil, "", fmt.Errorf("scan eikon: %w", err)
	}

	return frames, artistID, nil
}
