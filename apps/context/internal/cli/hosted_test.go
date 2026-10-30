package cli

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"
)

type transportFunc func(*http.Request) (*http.Response, error)

func (f transportFunc) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

func TestHostedOriginDefaultAndOverridePrecedence(t *testing.T) {
	path := isolatedConfig(t)
	const profileURL = "https://selfhost.example"
	c := Config{Profiles: map[string]Profile{}}
	oldTransport := http.DefaultTransport
	t.Cleanup(func() { http.DefaultTransport = oldTransport })
	var hosts []string
	http.DefaultTransport = transportFunc(func(r *http.Request) (*http.Response, error) {
		hosts = append(hosts, r.URL.Scheme+"://"+r.URL.Host)
		return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(`{}`))}, nil
	})
	assertOrigin := func(want string, args ...string) {
		t.Helper()
		before := len(hosts)
		code, out, errs := invoke(t, "", args...)
		if code != 0 || len(hosts) != before+1 || hosts[len(hosts)-1] != want {
			t.Fatalf("%v: code=%d hosts=%v out=%s err=%s", args, code, hosts, out, errs)
		}
	}
	assertOrigin(hostedAPIOrigin, "auth", "status")
	code, out, errs := invoke(t, "", "config", "show")
	var value map[string]any
	if code != 0 || json.Unmarshal([]byte(out), &value) != nil || value["url"] != hostedAPIOrigin {
		t.Fatalf("default config: %d %s %s", code, out, errs)
	}
	c.Profiles["default"] = Profile{URL: profileURL}
	if err := saveConfig(path, c); err != nil {
		t.Fatal(err)
	}
	assertOrigin(profileURL, "projects", "list")
	t.Setenv("MYCTX_URL", "https://environment.example")
	assertOrigin("https://environment.example", "projects", "list")
	assertOrigin("https://flag.example", "projects", "list", "--url", "https://flag.example")
}

func TestDefaultAuthenticationNeedsNoURLArgument(t *testing.T) {
	isolatedConfig(t)
	oldTransport := http.DefaultTransport
	t.Cleanup(func() { http.DefaultTransport = oldTransport })
	http.DefaultTransport = transportFunc(func(r *http.Request) (*http.Response, error) {
		if r.URL.Scheme+"://"+r.URL.Host != hostedAPIOrigin || r.URL.Path != "/auth/me" {
			t.Fatalf("unexpected request %s", r.URL)
		}
		return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(`{"id":"hosted-user"}`))}, nil
	})
	var out, errs strings.Builder
	code := Main(context.Background(), []string{"auth", "login", "--session-stdin"}, strings.NewReader("account-session"), &out, &errs, "test")
	if code != 0 {
		t.Fatalf("default login: %d %s", code, errs.String())
	}
}

func TestDefaultBrowserLoginChecksHostedGateway(t *testing.T) {
	isolatedConfig(t)
	oldTransport := http.DefaultTransport
	t.Cleanup(func() { http.DefaultTransport = oldTransport })
	http.DefaultTransport = transportFunc(func(r *http.Request) (*http.Response, error) {
		if r.URL.Scheme+"://"+r.URL.Host != hostedAPIOrigin || r.URL.Path != "/auth/cli/github" || r.Header.Get("Cookie") != "" {
			t.Fatalf("unexpected preflight %s", r.URL)
		}
		return &http.Response{StatusCode: 404, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(`{"error":"Not Found"}`))}, nil
	})
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	var out, errs strings.Builder
	code := Main(ctx, []string{"auth", "login", "--no-browser"}, strings.NewReader(""), &out, &errs, "test")
	var payload map[string]any
	if code != 1 || json.Unmarshal([]byte(errs.String()), &payload) != nil || payload["status"] != float64(404) || !strings.Contains(errs.String(), "does not support CLI login") {
		t.Fatalf("hosted browser login: %d %s", code, errs.String())
	}
}
