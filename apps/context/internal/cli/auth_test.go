package cli

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/cookiejar"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"
)

type loginWriter struct{ urls chan string }

func (w loginWriter) Write(b []byte) (int, error) {
	for _, line := range strings.Split(string(b), "\n") {
		if strings.HasPrefix(line, "http") {
			w.urls <- line
		}
	}
	return len(b), nil
}
func TestBrowserLogin(t *testing.T) {
	for _, tc := range []struct {
		missing bool
		web     string
	}{{false, ""}, {true, ""}, {false, "https://override.example"}} {
		wrongCookie := tc.missing
		t.Run(fmt.Sprint(wrongCookie, tc.web), func(t *testing.T) {
			gateway := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				switch r.URL.Path {
				case "/auth/cli/github":
					if r.Header.Get("Cookie") != "" || r.Header.Get("Authorization") != "" {
						t.Error("preflight leaked credentials")
					}
					w.Header().Set("Location", mockAuthorizationURL(r.URL.Query().Get("return_to")))
					w.WriteHeader(http.StatusSeeOther)
				case "/auth/confirm":
					if r.URL.Query().Get("token") != "handoff" {
						t.Error("wrong handoff")
					}
					w.Header().Set("X-Context-Frontend-Origin", "https://frontend.example")
					if !wrongCookie {
						http.SetCookie(w, &http.Cookie{Name: "vapor-session", Value: "credential"})
					}
					fmt.Fprint(w, `{"id":"user"}`)
				case "/auth/me":
					cookie, err := r.Cookie("vapor-session")
					if err != nil || cookie.Value != "credential" {
						t.Error("missing session")
					}
					fmt.Fprint(w, `{"id":"user"}`)
				default:
					t.Errorf("unexpected route %s", r.URL.Path)
				}
			}))
			defer gateway.Close()
			ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
			defer cancel()
			urls := make(chan string, 1)
			result := make(chan error, 1)
			client := newClient(gateway.URL, "old-session", time.Second)
			client.WebOrigin = tc.web
			expectedOrigin := tc.web
			if expectedOrigin == "" {
				expectedOrigin = "https://frontend.example"
			}
			go func() {
				session, err := browserLogin(ctx, client, true, loginWriter{urls})
				if !wrongCookie && (session != "credential" || client.WebOrigin != expectedOrigin) {
					result <- fmt.Errorf("bad credentials or frontend origin")
					return
				}
				result <- err
			}()
			login := <-urls
			u, err := url.Parse(login)
			if err != nil {
				t.Fatal(err)
			}
			if u.Host != "github.com" || u.Path != "/login/oauth/authorize" {
				t.Fatal(u.Path)
			}
			callback := callbackFromAuthorization(t, u)
			q := callback.Query()
			nonce := q.Get("state")
			q.Set("state", "invalid")
			q.Set("auth_token", "handoff")
			callback.RawQuery = q.Encode()
			resp, err := http.Get(callback.String())
			if err != nil {
				t.Fatal(err)
			}
			io.Copy(io.Discard, resp.Body)
			resp.Body.Close()
			if resp.StatusCode != 400 {
				t.Fatal(resp.StatusCode)
			}
			q.Set("state", nonce)
			callback.RawQuery = q.Encode()
			resp, err = http.Get(callback.String())
			if err != nil {
				t.Fatal(err)
			}
			resp.Body.Close()
			err = <-result
			if wrongCookie {
				if err == nil {
					t.Fatal("missing cookie accepted")
				}
			} else if err != nil {
				t.Fatal(err)
			}
		})
	}
}
func TestLoginCancellation(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	_, err := browserLogin(ctx, newClient("https://api.example", "", time.Second), true, io.Discard)
	if err != context.Canceled {
		t.Fatal(err)
	}
}
func TestTransportErrorDoesNotLeakHandoff(t *testing.T) {
	c := newClient("http://127.0.0.1:1", "", time.Second)
	_, _, err := c.request(context.Background(), "GET", "/auth/confirm", url.Values{"token": {"secret"}}, nil)
	if err == nil || strings.Contains(err.Error(), "secret") {
		t.Fatal(err)
	}
}
func TestOperationsJSON(t *testing.T) {
	b, err := json.Marshal(Operations)
	if err != nil || !json.Valid(b) {
		t.Fatal(err)
	}
}

func TestBrowserLoginDenial(t *testing.T) {
	gateway := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Location", mockAuthorizationURL(r.URL.Query().Get("return_to")))
		w.WriteHeader(http.StatusFound)
	}))
	defer gateway.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	urls := make(chan string, 1)
	result := make(chan error, 1)
	go func() {
		_, err := browserLogin(ctx, newClient(gateway.URL, "", time.Second), true, loginWriter{urls})
		result <- err
	}()
	login, _ := url.Parse(<-urls)
	callback := callbackFromAuthorization(t, login)
	q := callback.Query()
	q.Set("error", "access_denied")
	callback.RawQuery = q.Encode()
	resp, err := http.Get(callback.String())
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if err = <-result; err == nil || !strings.Contains(err.Error(), "declined") {
		t.Fatalf("expected immediate denial, got %v", err)
	}
}

// The production server signs this callback inside opaque OAuth state. A mock may
// carry it directly so tests can simulate GitHub returning to the bound listener.
func mockAuthorizationURL(callback string) string {
	return "https://github.com/login/oauth/authorize?" + url.Values{"client_id": {"test"}, "state": {callback}}.Encode()
}

func callbackFromAuthorization(t *testing.T, authorization *url.URL) *url.URL {
	t.Helper()
	callback, err := url.Parse(authorization.Query().Get("state"))
	if err != nil || callback.Host == "" {
		t.Fatalf("missing callback in mock OAuth state: %v", err)
	}
	return callback
}

func TestLoginPreflightFailures(t *testing.T) {
	cases := []struct {
		name     string
		status   int
		location string
		message  string
	}{
		{"missing route", 404, "", "deploy the accompanying Gateway"},
		{"unauthorized", 401, "", "HTTP 401"},
		{"forbidden", 403, "", "HTTP 403"},
		{"server error", 500, "", "HTTP 500"},
		{"HTML success", 200, "", "expected a GitHub authorization redirect"},
		{"missing location", 303, "", "invalid GitHub authorization redirect"},
		{"missing state", 303, "https://github.com/login/oauth/authorize?client_id=test", "invalid GitHub authorization redirect"},
		{"missing client ID", 303, "https://github.com/login/oauth/authorize?state=test", "invalid GitHub authorization redirect"},
		{"duplicate state", 303, "https://github.com/login/oauth/authorize?client_id=test&state=a&state=b", "invalid GitHub authorization redirect"},
		{"wrong host", 303, "https://evil.test/login/oauth/authorize", "invalid GitHub authorization redirect"},
		{"userinfo", 303, "https://user:password@github.com/login/oauth/authorize", "invalid GitHub authorization redirect"},
		{"alternate port", 303, "https://github.com:443/login/oauth/authorize", "invalid GitHub authorization redirect"},
		{"HTTP", 303, "http://github.com/login/oauth/authorize", "invalid GitHub authorization redirect"},
		{"wrong path", 303, "https://github.com/login", "invalid GitHub authorization redirect"},
		{"fragment", 303, "https://github.com/login/oauth/authorize#secret", "invalid GitHub authorization redirect"},
		{"relative", 303, "/login/oauth/authorize", "invalid GitHub authorization redirect"},
		{"malformed", 303, "https://github.com/%zz", "invalid GitHub authorization redirect"},
		{"unexpected permanent redirect", 301, "https://github.com/login/oauth/authorize", "HTTP 301"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var callback string
			gateway := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				callback = r.URL.Query().Get("return_to")
				if r.URL.Path != "/auth/cli/github" || r.Header.Get("Cookie") != "" {
					t.Error("incorrect or authenticated preflight")
				}
				if tc.location != "" {
					w.Header().Set("Location", tc.location)
				}
				w.WriteHeader(tc.status)
				fmt.Fprint(w, `{"error":"gateway detail"}`)
			}))
			defer gateway.Close()
			ctx, cancel := context.WithTimeout(context.Background(), time.Second)
			defer cancel()
			client := newClient(gateway.URL, "saved-secret", time.Second)
			// Cookie jars must not reintroduce credentials into the anonymous request.
			client.HTTP.Jar, _ = cookiejar.New(nil)
			gatewayURL, _ := url.Parse(gateway.URL)
			client.HTTP.Jar.SetCookies(gatewayURL, []*http.Cookie{{Name: "vapor-session", Value: "jar-secret"}})
			var diagnostics bytes.Buffer
			_, err := browserLogin(ctx, client, true, &diagnostics)
			if err == nil || !strings.Contains(err.Error(), tc.message) {
				t.Fatalf("got %v, expected %q", err, tc.message)
			}
			if diagnostics.Len() != 0 {
				t.Fatalf("browser URL emitted before preflight success: %s", diagnostics.String())
			}
			if tc.status >= 400 {
				var api *APIError
				if !errors.As(err, &api) || api.Status != tc.status {
					t.Fatalf("lost structured status: %v", err)
				}
			}
			if client.Session != "saved-secret" {
				t.Fatal("preflight mutated saved session")
			}
			callbackURL, parseErr := url.Parse(callback)
			if parseErr != nil || callbackURL.Host == "" {
				t.Fatalf("missing preflight callback: %q", callback)
			}
			listener, listenErr := net.Listen("tcp4", callbackURL.Host)
			if listenErr != nil {
				t.Fatalf("failed login leaked callback listener: %v", listenErr)
			}
			listener.Close()
		})
	}
}

func TestLoginPreflightCancellation(t *testing.T) {
	started := make(chan struct{})
	gateway := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		close(started)
		<-r.Context().Done()
	}))
	defer gateway.Close()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	result := make(chan error, 1)
	go func() {
		_, err := browserLogin(ctx, newClient(gateway.URL, "", time.Second), true, io.Discard)
		result <- err
	}()
	<-started
	cancel()
	if err := <-result; err != context.Canceled {
		t.Fatalf("got %v", err)
	}
}
