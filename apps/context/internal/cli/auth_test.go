package cli

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
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
			client := newClient(gateway.URL, "", time.Second)
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
			if u.Path != "/auth/cli/github" {
				t.Fatal(u.Path)
			}
			callback, _ := url.Parse(u.Query().Get("return_to"))
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
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	urls := make(chan string, 1)
	result := make(chan error, 1)
	go func() {
		_, err := browserLogin(ctx, newClient("https://api.example", "", time.Second), true, loginWriter{urls})
		result <- err
	}()
	login, _ := url.Parse(<-urls)
	callback, _ := url.Parse(login.Query().Get("return_to"))
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
