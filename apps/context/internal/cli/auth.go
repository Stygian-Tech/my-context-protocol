package cli

import (
	"context"
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os/exec"
	"runtime"
	"strings"
	"sync"
	"time"
)

func browserLogin(ctx context.Context, client *Client, noBrowser bool, diagnostics io.Writer) (string, error) {
	if err := ctx.Err(); err != nil {
		return "", err
	}
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		return "", err
	}
	defer listener.Close()
	nonceBytes := make([]byte, 32)
	if _, err = rand.Read(nonceBytes); err != nil {
		return "", err
	}
	nonce := base64.RawURLEncoding.EncodeToString(nonceBytes)
	callback := "http://" + listener.Addr().String() + "/callback?state=" + nonce
	loginURL, err := cliAuthorizationURL(ctx, client, callback)
	if err != nil {
		return "", err
	}
	if err := ctx.Err(); err != nil {
		return "", err
	}
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
			http.Error(w, "GitHub authorization failed. Return to MyContextCLI to retry.", http.StatusBadRequest)
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
		fmt.Fprintln(w, "Authorization received. You can return to MyContextCLI.")
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
	if origin := resp.Header.Get("X-Context-Frontend-Origin"); origin != "" && client.WebOrigin == "" {
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

// Fetch authorization metadata without sending a stored session or following redirects.
// The server signs the callback into OAuth state; no browser initiation cookie is needed.
func cliAuthorizationURL(ctx context.Context, client *Client, callback string) (string, error) {
	anonymous := *client
	anonymous.Session = ""
	httpClient := *client.HTTP
	httpClient.Jar = nil
	httpClient.CheckRedirect = func(_ *http.Request, _ []*http.Request) error { return http.ErrUseLastResponse }
	anonymous.HTTP = &httpClient
	_, response, err := anonymous.request(ctx, "GET", "/auth/cli/github", url.Values{"return_to": {callback}}, nil)
	if err != nil {
		if ctx.Err() != nil {
			return "", ctx.Err()
		}
		// net/http parses Location before CheckRedirect, even when redirects are
		// disabled. Do not print an untrusted malformed redirect URL in errors.
		if strings.Contains(err.Error(), "failed to parse Location header") {
			return "", fmt.Errorf("CLI login returned an invalid GitHub authorization redirect")
		}
		var api *APIError
		if errors.As(err, &api) && api.Status == http.StatusNotFound {
			return "", fmt.Errorf("server does not support CLI login; deploy the accompanying Gateway version or verify the API origin: %w", err)
		}
		if !errors.As(err, &api) || response == nil || (response.StatusCode != http.StatusFound && response.StatusCode != http.StatusSeeOther) {
			return "", err
		}
	}
	if response.StatusCode != http.StatusFound && response.StatusCode != http.StatusSeeOther {
		return "", fmt.Errorf("CLI login expected a GitHub authorization redirect; verify the API origin and Gateway version")
	}
	location := response.Header.Get("Location")
	target, parseErr := url.Parse(location)
	if parseErr != nil || target.Scheme != "https" || target.Host != "github.com" || target.User != nil || target.EscapedPath() != "/login/oauth/authorize" || target.Fragment != "" {
		return "", fmt.Errorf("CLI login returned an invalid GitHub authorization redirect")
	}
	query, queryErr := url.ParseQuery(target.RawQuery)
	if queryErr != nil || len(query["client_id"]) != 1 || query.Get("client_id") == "" || len(query["state"]) != 1 || query.Get("state") == "" {
		return "", fmt.Errorf("CLI login returned an invalid GitHub authorization redirect")
	}
	return target.String(), nil
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
