package cli

import (
	"context"
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os/exec"
	"runtime"
	"sync"
	"time"
)

func browserLogin(ctx context.Context, client *Client, noBrowser bool, diagnostics io.Writer) (string, error) {
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		return "", err
	}
	nonceBytes := make([]byte, 32)
	if _, err = rand.Read(nonceBytes); err != nil {
		listener.Close()
		return "", err
	}
	nonce := base64.RawURLEncoding.EncodeToString(nonceBytes)
	callback := "http://" + listener.Addr().String() + "/callback?state=" + nonce
	loginURL := client.Origin + "/auth/cli/github?" + url.Values{"return_to": {callback}}.Encode()
	type loginResult struct {
		token string
		err   error
	}
	results := make(chan loginResult, 1)
	var once sync.Once
	mux := http.NewServeMux()
	mux.HandleFunc("/callback", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Referrer-Policy", "no-referrer")
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		q := r.URL.Query()
		if r.Method != "GET" || len(q["state"]) != 1 || subtle.ConstantTimeCompare([]byte(q.Get("state")), []byte(nonce)) != 1 {
			http.Error(w, "Invalid login state", http.StatusBadRequest)
			return
		}
		if len(q["error"]) == 1 && q.Get("error") != "" {
			once.Do(func() {
				results <- loginResult{err: fmt.Errorf("GitHub authorization was declined or failed; run auth login to try again")}
			})
			http.Error(w, "GitHub authorization failed. Return to Context to retry.", http.StatusBadRequest)
			return
		}
		if len(q["auth_token"]) != 1 || q.Get("auth_token") == "" {
			http.Error(w, "Missing authorization token", http.StatusBadRequest)
			return
		}
		accepted := false
		once.Do(func() { results <- loginResult{token: q.Get("auth_token")}; accepted = true })
		if !accepted {
			http.Error(w, "Login already received", http.StatusConflict)
			return
		}
		fmt.Fprintln(w, "Authorization received. You can return to Context.")
	})
	server := &http.Server{Handler: mux, ReadHeaderTimeout: 5 * time.Second, IdleTimeout: 5 * time.Second}
	defer server.Close()
	failures := make(chan error, 1)
	go func() { failures <- server.Serve(listener) }()
	fmt.Fprintln(diagnostics, "Open this URL to authenticate with GitHub:\n"+loginURL)
	if !noBrowser {
		if err = openBrowser(loginURL); err != nil {
			fmt.Fprintln(diagnostics, "Browser could not open automatically; open the URL above.")
		}
	}
	timer := time.NewTimer(5 * time.Minute)
	defer timer.Stop()
	var token string
	select {
	case result := <-results:
		if result.err != nil {
			return "", result.err
		}
		token = result.token
	case <-ctx.Done():
		return "", ctx.Err()
	case <-timer.C:
		return "", fmt.Errorf("login timed out after 5 minutes")
	case err = <-failures:
		return "", fmt.Errorf("login callback server: %w", err)
	}
	_, resp, err := client.request(ctx, "GET", "/auth/confirm", url.Values{"token": {token}}, nil)
	if err != nil {
		return "", err
	}
	var session string
	for _, cookie := range resp.Cookies() {
		if cookie.Name == "vapor-session" && cookie.Value != "" {
			session = cookie.Value
		}
	}
	if session == "" {
		return "", fmt.Errorf("authorization did not return a session cookie")
	}
	if origin := resp.Header.Get("X-Context-Frontend-Origin"); origin != "" {
		if validated, e := validateURL(origin); e == nil {
			client.WebOrigin = validated
		}
	}
	client.Session = session
	if _, _, err = client.request(ctx, "GET", "/auth/me", nil, nil); err != nil {
		return "", err
	}
	return session, nil
}
func openBrowser(raw string) error {
	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "darwin":
		cmd = exec.Command("open", raw)
	case "windows":
		cmd = exec.Command("rundll32", "url.dll,FileProtocolHandler", raw)
	default:
		cmd = exec.Command("xdg-open", raw)
	}
	// Reap the opener without blocking callback processing.
	if err := cmd.Start(); err != nil {
		return err
	}
	go func() { _ = cmd.Wait() }()
	return nil
}
