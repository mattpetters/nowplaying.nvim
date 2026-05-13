package spotify

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os/exec"
	"runtime"
	"time"
)

const (
	defaultClientID = "52fa8f0460d447ae89737c655891a18a"
	redirectPort    = 48721
	redirectURI     = "http://127.0.0.1:48721/callback"
	authURL         = "https://accounts.spotify.com/authorize"
	authScopes      = "user-read-playback-state user-modify-playback-state user-library-modify user-library-read"
)

type authFlow struct {
	clientID string
	tokens   *tokenStore
}

func newAuthFlow(clientID string, tokens *tokenStore) *authFlow {
	if clientID == "" {
		clientID = defaultClientID
	}
	return &authFlow{clientID: clientID, tokens: tokens}
}

func (a *authFlow) startAndWait(ctx context.Context) (string, error) {
	verifier, challenge, err := generatePKCE()
	if err != nil {
		return "", fmt.Errorf("generate PKCE: %w", err)
	}

	state := randomString(32)

	params := url.Values{
		"client_id":             {a.clientID},
		"response_type":         {"code"},
		"redirect_uri":          {redirectURI},
		"scope":                 {authScopes},
		"code_challenge_method": {"S256"},
		"code_challenge":        {challenge},
		"state":                 {state},
	}
	authPageURL := authURL + "?" + params.Encode()

	listener, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", redirectPort))
	if err != nil {
		return "", fmt.Errorf("bind port %d: %w", redirectPort, err)
	}

	done := make(chan error, 1)

	mux := http.NewServeMux()
	mux.HandleFunc("/callback", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Query().Get("state") != state {
			http.Error(w, "state mismatch", http.StatusBadRequest)
			done <- fmt.Errorf("state mismatch")
			return
		}
		if e := r.URL.Query().Get("error"); e != "" {
			desc := r.URL.Query().Get("error_description")
			if desc == "" {
				desc = e
			}
			http.Error(w, desc, http.StatusBadRequest)
			done <- fmt.Errorf("auth denied: %s", desc)
			return
		}
		code := r.URL.Query().Get("code")
		if code == "" {
			http.Error(w, "no code", http.StatusBadRequest)
			done <- fmt.Errorf("no authorization code")
			return
		}

		if err := a.exchangeCode(code, verifier); err != nil {
			http.Error(w, "token exchange failed", http.StatusInternalServerError)
			done <- err
			return
		}

		w.Header().Set("Content-Type", "text/html")
		fmt.Fprint(w, successHTML)
		done <- nil
	})

	srv := &http.Server{Handler: mux}
	go srv.Serve(listener)
	defer srv.Close()

	openBrowser(authPageURL)

	select {
	case err := <-done:
		return authPageURL, err
	case <-ctx.Done():
		return authPageURL, ctx.Err()
	case <-time.After(120 * time.Second):
		return authPageURL, fmt.Errorf("auth timed out")
	}
}

func (a *authFlow) exchangeCode(code, verifier string) error {
	form := url.Values{
		"grant_type":    {"authorization_code"},
		"code":          {code},
		"redirect_uri":  {redirectURI},
		"client_id":     {a.clientID},
		"code_verifier": {verifier},
	}

	resp, err := http.PostForm(tokenURL, form)
	if err != nil {
		return fmt.Errorf("token exchange: %w", err)
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	var result struct {
		AccessToken  string `json:"access_token"`
		RefreshToken string `json:"refresh_token"`
		ExpiresIn    int    `json:"expires_in"`
		Error        string `json:"error"`
		ErrorDesc    string `json:"error_description"`
	}
	if err := json.Unmarshal(body, &result); err != nil {
		return fmt.Errorf("decode token response: %w", err)
	}
	if result.Error != "" {
		return fmt.Errorf("%s: %s", result.Error, result.ErrorDesc)
	}
	a.tokens.store(result.AccessToken, result.RefreshToken, result.ExpiresIn)
	return nil
}

func generatePKCE() (verifier, challenge string, err error) {
	verifier = randomString(128)
	hash := sha256.Sum256([]byte(verifier))
	challenge = base64.RawURLEncoding.EncodeToString(hash[:])
	return verifier, challenge, nil
}

func randomString(length int) string {
	const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
	b := make([]byte, length)
	_, _ = rand.Read(b)
	for i := range b {
		b[i] = chars[b[i]%byte(len(chars))]
	}
	return string(b)
}

func openBrowser(url string) {
	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "darwin":
		cmd = exec.Command("open", url)
	case "linux":
		cmd = exec.Command("xdg-open", url)
	default:
		cmd = exec.Command("cmd", "/c", "start", url)
	}
	_ = cmd.Start()
}

const successHTML = `<!DOCTYPE html>
<html>
<head><title>NowPlaying</title>
<style>
  body { font-family: -apple-system, system-ui, sans-serif; display: flex;
         justify-content: center; align-items: center; min-height: 100vh;
         margin: 0; background: #121212; color: #fff; }
  .card { text-align: center; padding: 2rem; }
  h1 { color: #1DB954; margin-bottom: 0.5rem; }
  p { color: #b3b3b3; }
</style></head>
<body>
  <div class="card">
    <h1>Authenticated</h1>
    <p>Return to the TUI — you can close this tab.</p>
  </div>
</body>
</html>`
