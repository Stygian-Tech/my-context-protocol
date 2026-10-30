package cli

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
)

func isolatedConfig(t *testing.T) string {
	t.Helper()
	for _, name := range []string{"CONTEXT_URL", "CONTEXT_WEB_URL", "CONTEXT_PROFILE", "CONTEXT_SESSION", "CONTEXT_PROJECT"} {
		t.Setenv(name, "")
		t.Setenv(strings.Replace(name, "CONTEXT_", "MYCTX_", 1), "")
	}
	path := filepath.Join(t.TempDir(), "context", "config.json")
	t.Setenv("CONTEXT_CONFIG", path)
	t.Setenv("MYCTX_CONFIG", "")
	return path
}

func invoke(t *testing.T, input string, args ...string) (int, string, string) {
	t.Helper()
	var out, errs bytes.Buffer
	code := Main(context.Background(), args, strings.NewReader(input), &out, &errs, "test-version")
	return code, out.String(), errs.String()
}

func TestNamedOperationPathQueryAndBody(t *testing.T) {
	isolatedConfig(t)
	t.Setenv("CONTEXT_SESSION", "session-secret")
	var calls int
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		if r.Method != "PATCH" || r.URL.Path != "/projects/project-1/releases/release-2/compiled-skills/skill-3" {
			t.Errorf("unexpected request: %s %s", r.Method, r.URL)
		}
		if values := r.URL.Query()["tag"]; len(values) != 2 || values[0] != "a b" || values[1] != "c&d" {
			t.Errorf("query = %v", r.URL.Query())
		}
		cookie, err := r.Cookie("vapor-session")
		if err != nil || cookie.Value != "session-secret" {
			t.Errorf("session cookie = %v, %v", cookie, err)
		}
		if r.Header.Get("Origin") != "https://context.example" || r.Header.Get("Content-Type") != "application/json" {
			t.Errorf("headers = %v", r.Header)
		}
		var body map[string]any
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body["summary"] != "updated" {
			t.Errorf("body = %v, %v", body, err)
		}
		w.Header().Set("Content-Type", "application/json")
		io.WriteString(w, `{"status":"ready"}`)
	}))
	defer server.Close()
	code, out, errs := invoke(t, "", "skills", "update", "--url", server.URL, "--web-url", "https://context.example", "--id", "project-1", "--release-id", "release-2", "--compiled-skill-id", "skill-3", "--query", "tag=a b", "--query", "tag=c&d", "--set", `summary="updated"`)
	if code != 0 || !strings.Contains(out, `"ready"`) || errs != "" || calls != 1 {
		t.Fatalf("code=%d out=%s errors=%s calls=%d", code, out, errs, calls)
	}
}

func TestSessionLoginPersistsPrivateConfigAndLogout(t *testing.T) {
	path := isolatedConfig(t)
	var logoutCalls int
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		cookie, err := r.Cookie("vapor-session")
		if err != nil || cookie.Value != "private-session" {
			t.Errorf("cookie = %v, %v", cookie, err)
		}
		if r.URL.Path == "/auth/logout" {
			logoutCalls++
			w.WriteHeader(http.StatusNoContent)
			return
		}
		io.WriteString(w, `{"id":"account-1"}`)
	}))
	defer server.Close()
	code, out, errs := invoke(t, "private-session\n", "auth", "login", "--session-stdin", "--url", server.URL, "--web-url", "https://context.example", "--profile", "work")
	if code != 0 || strings.Contains(out+errs, "private-session") {
		t.Fatalf("login: code=%d out=%s errors=%s", code, out, errs)
	}
	c, err := loadConfig(path)
	if err != nil || c.Profiles["work"].Session != "private-session" || c.Profiles["work"].URL != server.URL {
		t.Fatalf("saved config = %+v, %v", c, err)
	}
	for _, item := range []struct {
		path string
		mode os.FileMode
	}{{path, 0600}, {filepath.Dir(path), 0700}} {
		info, err := os.Stat(item.path)
		if err != nil || info.Mode().Perm() != item.mode {
			t.Fatalf("permissions %s: %v %v", item.path, info, err)
		}
	}
	code, out, errs = invoke(t, "", "config", "show", "--profile", "work")
	if code != 0 || strings.Contains(out+errs, "private-session") || !strings.Contains(out, `"authenticated":true`) {
		t.Fatalf("config show: code=%d out=%s errors=%s", code, out, errs)
	}
	code, out, errs = invoke(t, "", "auth", "logout", "--profile", "work")
	c, err = loadConfig(path)
	if code != 0 || err != nil || c.Profiles["work"].Session != "" || logoutCalls != 1 {
		t.Fatalf("logout: code=%d out=%s errors=%s config=%+v err=%v", code, out, errs, c, err)
	}
}

func TestProfileAndOriginCredentialIsolation(t *testing.T) {
	path := isolatedConfig(t)
	var cookies []string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		cookies = append(cookies, r.Header.Get("Cookie"))
		io.WriteString(w, `{}`)
	}))
	defer server.Close()
	c := Config{Profiles: map[string]Profile{
		"default": {URL: "https://other.example", WebURL: "https://old.example", Session: "other-secret", Project: "other-project"},
		"work":    {URL: server.URL, Session: "work-secret", Project: "work-project"},
	}}
	if err := saveConfig(path, c); err != nil {
		t.Fatal(err)
	}
	for _, args := range [][]string{{"auth", "me", "--profile", "work"}, {"auth", "me", "--url", server.URL}} {
		if code, out, errs := invoke(t, "", args...); code != 0 {
			t.Fatalf("code=%d out=%s errors=%s", code, out, errs)
		}
	}
	if len(cookies) != 2 || cookies[0] != "vapor-session=work-secret" || cookies[1] != "" {
		t.Fatalf("cookies=%v", cookies)
	}
	if code, _, errs := invoke(t, "", "config", "set", "--url", server.URL); code != 0 {
		t.Fatal(errs)
	}
	c, err := loadConfig(path)
	if err != nil || c.Profiles["default"].Session != "" || c.Profiles["default"].Project != "" || c.Profiles["default"].WebURL != "" || c.Profiles["work"].Session != "work-secret" {
		t.Fatalf("config=%+v err=%v", c, err)
	}
}

func TestAPIErrorsAreStructuredAndHaveStableExitCodes(t *testing.T) {
	isolatedConfig(t)
	for _, tc := range []struct {
		status, exit int
		code         string
	}{{401, 3, "unauthenticated"}, {403, 4, "forbidden"}, {429, 1, "request_failed"}, {500, 1, "request_failed"}} {
		t.Run(http.StatusText(tc.status), func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.WriteHeader(tc.status)
				io.WriteString(w, `{"error":"server detail"}`)
			}))
			defer server.Close()
			code, out, errs := invoke(t, "", "auth", "me", "--url", server.URL)
			var payload map[string]any
			if err := json.Unmarshal([]byte(errs), &payload); err != nil {
				t.Fatal(err)
			}
			if code != tc.exit || out != "" || payload["code"] != tc.code || payload["status"] != float64(tc.status) {
				t.Fatalf("code=%d out=%s errors=%s", code, out, errs)
			}
			if payload["details"].(map[string]any)["error"] != "server detail" {
				t.Fatalf("missing API detail: %s", errs)
			}
		})
	}
}

func TestRedirectNeverForwardsCredentials(t *testing.T) {
	isolatedConfig(t)
	t.Setenv("CONTEXT_SESSION", "secret")
	var targetCalls atomic.Int32
	target := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		targetCalls.Add(1)
		t.Errorf("unexpected redirect request with headers %v", r.Header)
	}))
	defer target.Close()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, target.URL+"/install", http.StatusFound)
	}))
	defer server.Close()
	code, out, errs := invoke(t, "", "github", "install", "--url", server.URL, "--query", "project_id=p1")
	if code != 0 || !strings.Contains(out, target.URL+"/install") || errs != "" || targetCalls.Load() != 0 {
		t.Fatalf("install: code=%d out=%s errors=%s", code, out, errs)
	}
	code, _, _ = invoke(t, "", "auth", "me", "--url", server.URL)
	if code != 1 || targetCalls.Load() != 0 {
		t.Fatalf("ordinary redirect code=%d calls=%d", code, targetCalls.Load())
	}
}

func TestInvalidInputDoesNotMakeRequests(t *testing.T) {
	isolatedConfig(t)
	var calls atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { calls.Add(1); io.WriteString(w, `{}`) }))
	defer server.Close()
	cases := [][]string{
		{"projects", "get"}, {"projects", "get", "--id", "../escape"},
		{"skills", "update", "--id", "p", "--release-id", "r"},
		{"projects", "create", "--data", "{"}, {"projects", "create", "--set", "name=unquoted"},
		{"projects", "list", "--query", "invalid"}, {"projects", "list", "--data", "{}"},
		{"projects", "list", "--timeout", "-1s"}, {"projects", "list", "--unknown"},
		{"api", "TRACE", "/projects"}, {"auth", "login", "--session-stdin"},
	}
	for _, args := range cases {
		t.Run(strings.Join(args, " "), func(t *testing.T) {
			args = append(append([]string{}, args...), "--url", server.URL)
			code, out, errs := invoke(t, "bad;cookie", args...)
			var payload map[string]any
			if json.Unmarshal([]byte(errs), &payload) != nil || code != 2 || out != "" || payload["code"] != "invalid_arguments" {
				t.Fatalf("code=%d out=%s errors=%s", code, out, errs)
			}
		})
	}
	if calls.Load() != 0 {
		t.Fatalf("invalid inputs made %d requests", calls.Load())
	}
}

func TestRequestBodySourcesAndOverrides(t *testing.T) {
	file := filepath.Join(t.TempDir(), "body.json")
	if err := os.WriteFile(file, []byte(`{"name":"file","nested":{"enabled":true}}`), 0600); err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct{ name, data, input string }{
		{"literal", `{"name":"literal"}`, ""}, {"stdin", "-", `{"name":"stdin"}`}, {"file", "@" + file, ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			body, err := requestBody(options{"data": {tc.data}, "set": {`name="override"`, `count=2`, `name="final"`}}, strings.NewReader(tc.input))
			var value map[string]any
			if err != nil || json.Unmarshal(body, &value) != nil || value["name"] != "final" || value["count"] != float64(2) {
				t.Fatalf("body=%s error=%v", body, err)
			}
			if tc.name == "file" && value["nested"].(map[string]any)["enabled"] != true {
				t.Fatalf("lost nested data: %s", body)
			}
		})
	}
	for _, data := range []string{"null", "[]", "true"} {
		if _, err := requestBody(options{"data": {data}, "set": {`name="x"`}}, strings.NewReader("")); err == nil {
			t.Errorf("accepted --set with %s", data)
		}
	}
}

func TestJSONNumbersPreserveExactPrecision(t *testing.T) {
	const large = "9007199254740993"
	t.Run("response", func(t *testing.T) {
		var out bytes.Buffer
		if err := emit(&out, []byte(`{"github_id":`+large+`}`), false); err != nil {
			t.Fatal(err)
		}
		if !strings.Contains(out.String(), large) {
			t.Fatalf("response integer precision lost: %s", out.String())
		}
	})
	t.Run("request with set", func(t *testing.T) {
		body, err := requestBody(options{"data": {`{"github_id":` + large + `}`}, "set": {`count=` + large}}, strings.NewReader(""))
		if err != nil {
			t.Fatal(err)
		}
		if strings.Count(string(body), large) != 2 {
			t.Fatalf("request integer precision lost: %s", body)
		}
	})
}

func TestRawPathsCannotEscapeConfiguredOrigin(t *testing.T) {
	isolatedConfig(t)
	var calls atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
	}))
	defer server.Close()
	for _, path := range []string{server.URL + "/projects", "//127.0.0.1/projects", "/projects#fragment"} {
		code, _, errs := invoke(t, "", "api", "GET", path, "--url", server.URL)
		if code == 0 || !strings.Contains(errs, "origin-relative") {
			t.Errorf("accepted raw path %s: code=%d errors=%s", path, code, errs)
		}
	}
	if calls.Load() != 0 {
		t.Fatalf("unsafe paths made %d requests", calls.Load())
	}
}
