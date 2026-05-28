package asciiart

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"image"
	"image/jpeg"
	"image/png"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// ─── Cache ────────────────────────────────────────────────────────────────
//
// Cache stores generated ASCII animations on disk, keyed by artist name.
// Each artist gets a directory under the cache root:
//
//	~/.cache/nowplaying/ascii/
//	├── {artist_hash}/
//	│   ├── source.jpg       # original artist image (saved for re-rendering)
//	│   ├── anim.eikon       # serialized animation frames
//	│   └── meta.json        # config + timestamp metadata

// Cache manages disk-backed storage of ASCII animations.
type Cache struct {
	RootDir string
}

// CacheMeta stores metadata about a cached animation.
type CacheMeta struct {
	Artist     string `json:"artist"`
	Config     Config `json:"config"`
	FrameCount int    `json:"frame_count"`
	CreatedAt  int64  `json:"created_at"` // unix timestamp
}

// NewCache creates a cache rooted at the given directory.
func NewCache(rootDir string) *Cache {
	return &Cache{RootDir: rootDir}
}

// DefaultCacheDir returns the default cache directory path.
func DefaultCacheDir() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, ".cache", "nowplaying", "ascii"), nil
}

// ArtistDir returns the cache directory for the given artist name.
func (c *Cache) ArtistDir(artist string) string {
	hash := artistHash(artist)
	return filepath.Join(c.RootDir, hash)
}

// Has returns true if a cached animation exists for the artist.
func (c *Cache) Has(artist string) bool {
	dir := c.ArtistDir(artist)
	animPath := filepath.Join(dir, "anim.eikon")
	_, err := os.Stat(animPath)
	return err == nil
}

// Load loads a cached animation for the given artist.
func (c *Cache) Load(artist string) ([]Frame, error) {
	dir := c.ArtistDir(artist)
	animPath := filepath.Join(dir, "anim.eikon")

	data, err := os.ReadFile(animPath)
	if err != nil {
		return nil, fmt.Errorf("cache load %s: %w", artist, err)
	}

	frames, _, err := DecodeEikonLines(data)
	if err != nil {
		return nil, fmt.Errorf("cache decode %s: %w", artist, err)
	}

	return frames, nil
}

// LoadMeta loads the metadata for a cached animation.
func (c *Cache) LoadMeta(artist string) (*CacheMeta, error) {
	dir := c.ArtistDir(artist)
	metaPath := filepath.Join(dir, "meta.json")

	data, err := os.ReadFile(metaPath)
	if err != nil {
		return nil, fmt.Errorf("cache meta %s: %w", artist, err)
	}

	var meta CacheMeta
	if err := json.Unmarshal(data, &meta); err != nil {
		return nil, fmt.Errorf("cache meta decode %s: %w", artist, err)
	}

	return &meta, nil
}

// Store saves an animation to the cache.
func (c *Cache) Store(artist string, frames []Frame, cfg Config) error {
	dir := c.ArtistDir(artist)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("cache mkdir %s: %w", artist, err)
	}

	// Write animation frames
	animData, err := EncodeEikon(frames, artist)
	if err != nil {
		return fmt.Errorf("cache encode %s: %w", artist, err)
	}
	animPath := filepath.Join(dir, "anim.eikon")
	if err := os.WriteFile(animPath, animData, 0644); err != nil {
		return fmt.Errorf("cache write %s: %w", artist, err)
	}

	// Write metadata
	meta := CacheMeta{
		Artist:     artist,
		Config:     cfg,
		FrameCount: len(frames),
		CreatedAt:  nowUnix(),
	}
	metaData, err := json.MarshalIndent(meta, "", "  ")
	if err != nil {
		return fmt.Errorf("cache meta marshal %s: %w", artist, err)
	}
	metaPath := filepath.Join(dir, "meta.json")
	if err := os.WriteFile(metaPath, metaData, 0644); err != nil {
		return fmt.Errorf("cache meta write %s: %w", artist, err)
	}

	return nil
}

// StoreSourceImage saves the original artist image to the cache for
// later re-rendering with different configs.
func (c *Cache) StoreSourceImage(artist string, img image.Image) error {
	dir := c.ArtistDir(artist)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("cache mkdir: %w", err)
	}

	path := filepath.Join(dir, "source.jpg")
	f, err := os.Create(path)
	if err != nil {
		return fmt.Errorf("create source image: %w", err)
	}
	defer f.Close()

	return jpeg.Encode(f, img, &jpeg.Options{Quality: 85})
}

// LoadSourceImage loads the cached source image for an artist.
func (c *Cache) LoadSourceImage(artist string) (image.Image, error) {
	dir := c.ArtistDir(artist)

	// Try jpg first, then png
	paths := []string{
		filepath.Join(dir, "source.jpg"),
		filepath.Join(dir, "source.png"),
	}

	for _, path := range paths {
		f, err := os.Open(path)
		if err != nil {
			continue
		}
		defer f.Close()

		ext := strings.ToLower(filepath.Ext(path))
		switch ext {
		case ".jpg", ".jpeg":
			img, _, err := image.Decode(f)
			if err != nil {
				return nil, fmt.Errorf("decode source jpg: %w", err)
			}
			return img, nil
		case ".png":
			img, err := png.Decode(f)
			if err != nil {
				return nil, fmt.Errorf("decode source png: %w", err)
			}
			return img, nil
		}
	}

	return nil, fmt.Errorf("no source image cached for %s", artist)
}

// Delete removes a cached animation for the given artist.
func (c *Cache) Delete(artist string) error {
	dir := c.ArtistDir(artist)
	return os.RemoveAll(dir)
}

// Clear removes all cached animations.
func (c *Cache) Clear() error {
	entries, err := os.ReadDir(c.RootDir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	for _, entry := range entries {
		if entry.IsDir() {
			_ = os.RemoveAll(filepath.Join(c.RootDir, entry.Name()))
		}
	}
	return nil
}

// List returns all cached artists.
func (c *Cache) List() ([]string, error) {
	entries, err := os.ReadDir(c.RootDir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}
	var artists []string
	for _, entry := range entries {
		if entry.IsDir() {
			// Try to read meta for the real artist name
			metaPath := filepath.Join(c.RootDir, entry.Name(), "meta.json")
			if data, err := os.ReadFile(metaPath); err == nil {
				var meta CacheMeta
				if json.Unmarshal(data, &meta) == nil && meta.Artist != "" {
					artists = append(artists, meta.Artist)
					continue
				}
			}
			artists = append(artists, entry.Name())
		}
	}
	return artists, nil
}

// ─── Helpers ─────────────────────────────────────────────────────────────

func artistHash(artist string) string {
	h := sha256.Sum256([]byte(strings.ToLower(strings.TrimSpace(artist))))
	return hex.EncodeToString(h[:8]) // 16-char hex, short enough to read
}

func nowUnix() int64 {
	return time.Now().Unix()
}
