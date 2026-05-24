package spotify

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const (
	apiBase  = "https://api.spotify.com/v1"
	tokenURL = "https://accounts.spotify.com/api/token"
)

type apiClient struct {
	tokens   *tokenStore
	clientID string
	http     *http.Client
}

func newAPIClient(tokens *tokenStore, clientID string) *apiClient {
	return &apiClient{
		tokens:   tokens,
		clientID: clientID,
		http:     &http.Client{Timeout: 10 * time.Second},
	}
}

type apiSearchResult struct {
	Tracks struct {
		Items []apiTrack `json:"items"`
	} `json:"tracks"`
}

type apiTrack struct {
	ID         string      `json:"id"`
	URI        string      `json:"uri"`
	Name       string      `json:"name"`
	DurationMS int64       `json:"duration_ms"`
	Artists    []apiArtist `json:"artists"`
	Album      apiAlbum    `json:"album"`
}

type apiArtist struct {
	Name string `json:"name"`
}

type apiAlbum struct {
	Name   string     `json:"name"`
	URI    string     `json:"uri"`
	Images []apiImage `json:"images"`
}

type apiImage struct {
	URL string `json:"url"`
}

func (c *apiClient) ensureToken() (string, error) {
	if !c.tokens.hasTokens() {
		return "", fmt.Errorf("not authenticated — press 'a' to login")
	}
	if !c.tokens.isExpired() {
		return c.tokens.accessToken(), nil
	}
	if err := c.refreshAccessToken(); err != nil {
		return "", err
	}
	return c.tokens.accessToken(), nil
}

func (c *apiClient) refreshAccessToken() error {
	rt := c.tokens.refreshToken()
	if rt == "" {
		return fmt.Errorf("no refresh token")
	}

	form := url.Values{
		"grant_type":    {"refresh_token"},
		"refresh_token": {rt},
		"client_id":     {c.clientID},
	}

	resp, err := c.http.PostForm(tokenURL, form)
	if err != nil {
		return fmt.Errorf("refresh request: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()

	body, _ := io.ReadAll(resp.Body)
	var result struct {
		AccessToken  string `json:"access_token"`
		RefreshToken string `json:"refresh_token"`
		ExpiresIn    int    `json:"expires_in"`
		Error        string `json:"error"`
		ErrorDesc    string `json:"error_description"`
	}
	if err := json.Unmarshal(body, &result); err != nil {
		return fmt.Errorf("decode refresh response: %w", err)
	}
	if result.Error != "" {
		return fmt.Errorf("refresh: %s", result.ErrorDesc)
	}
	c.tokens.store(result.AccessToken, result.RefreshToken, result.ExpiresIn)
	return nil
}

func (c *apiClient) request(method, path string, body []byte) (*http.Response, error) {
	token, err := c.ensureToken()
	if err != nil {
		return nil, err
	}

	var bodyReader io.Reader
	if body != nil {
		bodyReader = bytes.NewReader(body)
	}
	req, err := http.NewRequest(method, apiBase+path, bodyReader)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}

	if resp.StatusCode == 401 {
		_ = resp.Body.Close()
		if err := c.refreshAccessToken(); err != nil {
			return nil, fmt.Errorf("token refresh after 401: %w", err)
		}
		token = c.tokens.accessToken()
		if body != nil {
			bodyReader = bytes.NewReader(body)
		}
		req, _ = http.NewRequest(method, apiBase+path, bodyReader)
		req.Header.Set("Authorization", "Bearer "+token)
		if body != nil {
			req.Header.Set("Content-Type", "application/json")
		}
		return c.http.Do(req)
	}

	return resp, nil
}

func (c *apiClient) search(query string, limit int) ([]apiTrack, error) {
	if limit <= 0 {
		limit = 10
	}
	params := url.Values{
		"q":     {query},
		"type":  {"track"},
		"limit": {fmt.Sprintf("%d", limit)},
	}

	resp, err := c.request("GET", "/search?"+params.Encode(), nil)
	if err != nil {
		return nil, err
	}
	defer func() { _ = resp.Body.Close() }()

	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("search API %d: %s", resp.StatusCode, string(body))
	}

	var result apiSearchResult
	if err := json.Unmarshal(body, &result); err != nil {
		return nil, fmt.Errorf("decode search: %w", err)
	}
	return result.Tracks.Items, nil
}

func (c *apiClient) isTrackSaved(id string) (bool, error) {
	params := url.Values{"ids": {id}}
	resp, err := c.request("GET", "/me/tracks/contains?"+params.Encode(), nil)
	if err != nil {
		return false, err
	}
	defer func() { _ = resp.Body.Close() }()

	body, _ := io.ReadAll(resp.Body)
	var result []bool
	if err := json.Unmarshal(body, &result); err != nil {
		return false, err
	}
	if len(result) > 0 {
		return result[0], nil
	}
	return false, nil
}

func (c *apiClient) saveTrack(id string) error {
	data, _ := json.Marshal(map[string]any{"ids": []string{id}})
	resp, err := c.request("PUT", "/me/tracks", data)
	if err != nil {
		return err
	}
	defer func() { _ = resp.Body.Close() }()
	_, _ = io.ReadAll(resp.Body)
	if resp.StatusCode >= 400 {
		return fmt.Errorf("save track: HTTP %d", resp.StatusCode)
	}
	return nil
}

func (c *apiClient) removeTrack(id string) error {
	data, _ := json.Marshal(map[string]any{"ids": []string{id}})
	resp, err := c.request("DELETE", "/me/tracks", data)
	if err != nil {
		return err
	}
	defer func() { _ = resp.Body.Close() }()
	_, _ = io.ReadAll(resp.Body)
	if resp.StatusCode >= 400 {
		return fmt.Errorf("remove track: HTTP %d", resp.StatusCode)
	}
	return nil
}

func (c *apiClient) play(uri string) error {
	var body map[string]any
	if strings.HasPrefix(uri, "spotify:track:") {
		body = map[string]any{"uris": []string{uri}}
	} else {
		body = map[string]any{"context_uri": uri}
	}
	data, _ := json.Marshal(body)
	resp, err := c.request("PUT", "/me/player/play", data)
	if err != nil {
		return err
	}
	defer func() { _ = resp.Body.Close() }()
	_, _ = io.ReadAll(resp.Body)
	if resp.StatusCode >= 400 {
		return fmt.Errorf("play: HTTP %d", resp.StatusCode)
	}
	return nil
}

func (c *apiClient) hasTokens() bool {
	return c.tokens.hasTokens()
}
