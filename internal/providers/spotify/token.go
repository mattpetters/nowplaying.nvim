package spotify

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"
)

type tokenData struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	ExpiresAt    int64  `json:"expires_at"`
	Scope        string `json:"scope"`
	TokenType    string `json:"token_type"`
	StoredAt     int64  `json:"stored_at"`
}

type tokenStore struct {
	mu     sync.RWMutex
	path   string
	tokens *tokenData
}

func newTokenStore() *tokenStore {
	return &tokenStore{path: defaultTokenPath()}
}

func defaultTokenPath() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return filepath.Join(home, ".local", "share", "nvim", "nowplaying.nvim", "spotify_tokens.json")
}

func (s *tokenStore) load() error {
	s.mu.Lock()
	defer s.mu.Unlock()

	data, err := os.ReadFile(s.path)
	if err != nil {
		return fmt.Errorf("read token file: %w", err)
	}
	var t tokenData
	if err := json.Unmarshal(data, &t); err != nil {
		return fmt.Errorf("decode token file: %w", err)
	}
	s.tokens = &t
	return nil
}

func (s *tokenStore) save(t *tokenData) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	dir := filepath.Dir(s.path)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return fmt.Errorf("create token dir: %w", err)
	}

	data, err := json.MarshalIndent(t, "", "  ")
	if err != nil {
		return fmt.Errorf("encode tokens: %w", err)
	}
	if err := os.WriteFile(s.path, data, 0o600); err != nil {
		return fmt.Errorf("write token file: %w", err)
	}
	s.tokens = t
	return nil
}

func (s *tokenStore) accessToken() string {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if s.tokens == nil {
		return ""
	}
	return s.tokens.AccessToken
}

func (s *tokenStore) refreshToken() string {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if s.tokens == nil {
		return ""
	}
	return s.tokens.RefreshToken
}

func (s *tokenStore) isExpired() bool {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if s.tokens == nil {
		return true
	}
	return time.Now().Unix() >= s.tokens.ExpiresAt
}

func (s *tokenStore) hasTokens() bool {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.tokens != nil && s.tokens.AccessToken != ""
}

func (s *tokenStore) store(accessToken, refreshToken string, expiresIn int) {
	now := time.Now().Unix()
	rt := refreshToken

	s.mu.RLock()
	if rt == "" && s.tokens != nil {
		rt = s.tokens.RefreshToken
	}
	s.mu.RUnlock()

	t := &tokenData{
		AccessToken:  accessToken,
		RefreshToken: rt,
		ExpiresAt:    now + int64(expiresIn) - 60,
		TokenType:    "Bearer",
		StoredAt:     now,
	}
	_ = s.save(t)
}
