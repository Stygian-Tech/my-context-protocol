package cli

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestHumanErrorsAreDefault(t *testing.T) {
	isolatedConfig(t)
	for _, tc := range []struct {
		name               string
		status, exit       int
		body, detail, hint string
	}{
		{"unauthenticated", 401, 3, `{"error":"Your session expired","session":"private-secret"}`, "Your session expired", "myctx auth login"},
		{"forbidden", 403, 4, `{"reason":"Administrator access required"}`, "Administrator access required", "permissions"},
		{"rate limit", 429, 1, `{"message":"Too many requests"}`, "Too many requests", "Wait before retrying"},
		{"server", 503, 1, `{"reason":"Gateway unavailable"}`, "Gateway unavailable", "connection"},
		{"unstructured", 500, 1, `<html>private-secret</html>`, "HTTP 500", "connection"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(tc.status); io.WriteString(w, tc.body) }))
			defer server.Close()
			var out, errs bytes.Buffer
			code := Main(context.Background(), []string{"auth", "me", "--url", server.URL}, strings.NewReader(""), &out, &errs, "test")
			if code != tc.exit || out.Len() != 0 || !strings.HasPrefix(errs.String(), "Error: ") || !strings.Contains(errs.String(), tc.detail) || !strings.Contains(errs.String(), "Hint: ") || !strings.Contains(errs.String(), tc.hint) || strings.Contains(errs.String(), "private-secret") || json.Valid(errs.Bytes()) {
				t.Fatalf("code=%d out=%s errors=%s", code, out.String(), errs.String())
			}
		})
	}
}

func TestErrorFormatFlagRespectsValuesAndParseFailures(t *testing.T) {
	isolatedConfig(t)
	for _, tc := range []struct {
		name string
		args []string
		json bool
	}{
		{"before command", []string{"--json", "unknown"}, true},
		{"after parse failure", []string{"--unknown", "--json"}, true},
		{"after duplicate flag", []string{"--profile", "a", "--profile", "b", "--json"}, true},
		{"data value", []string{"projects", "create", "--data", "--json"}, false},
		{"profile value", []string{"unknown", "--profile", "--json"}, false},
		{"inline value", []string{"unknown", "--data=--json"}, false},
		{"data value then flag", []string{"projects", "create", "--data", "--json", "--json"}, true},
		{"boolean with value rejected", []string{"--json=true"}, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var out, errs bytes.Buffer
			code := Main(context.Background(), tc.args, strings.NewReader(""), &out, &errs, "test")
			if code != 2 || out.Len() != 0 || json.Valid(errs.Bytes()) != tc.json {
				t.Fatalf("code=%d out=%s errors=%s", code, out.String(), errs.String())
			}
			if tc.json {
				var payload map[string]any
				if err := json.Unmarshal(errs.Bytes(), &payload); err != nil || payload["code"] != "invalid_arguments" {
					t.Fatalf("errors=%s err=%v", errs.String(), err)
				}
			} else if !strings.Contains(errs.String(), "Hint: Run myctx help") {
				t.Fatalf("missing usage hint: %s", errs.String())
			}
		})
	}
}

func TestErrorFormattingPreservesSuccessJSON(t *testing.T) {
	isolatedConfig(t)
	for _, args := range [][]string{{"version"}, {"--json", "version"}, {"version", "--json"}} {
		var out, errs bytes.Buffer
		if code := Main(context.Background(), args, strings.NewReader(""), &out, &errs, "test"); code != 0 || errs.Len() != 0 || !json.Valid(out.Bytes()) {
			t.Fatalf("code=%d out=%s errors=%s", code, out.String(), errs.String())
		}
	}
}

func TestHumanErrorSanitizesServerControlCharacters(t *testing.T) {
	var out bytes.Buffer
	writeHumanError(&out, &APIError{Status: 400, Body: json.RawMessage(`{"error":"Bad\u001b[2J\nrequest"}`)}, 1)
	if strings.Contains(out.String(), "\x1b") || strings.Contains(out.String(), "J\nrequest") || !strings.Contains(out.String(), "Bad [2J request") {
		t.Fatalf("unsafe output: %q", out.String())
	}
}

func TestHumanCanceledError(t *testing.T) {
	var out bytes.Buffer
	writeHumanError(&out, context.Canceled, 130)
	if !strings.Contains(out.String(), "context canceled") || !strings.Contains(out.String(), "again when ready") {
		t.Fatal(out.String())
	}
}
