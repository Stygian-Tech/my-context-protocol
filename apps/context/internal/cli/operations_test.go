package cli

import (
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"testing"
)

// This comparison deliberately reads the canonical registration file instead of
// duplicating an expected route list, so new management routes fail CI until the
// CLI exposes them.
func TestOperationsCoverGatewayManagementRoutes(t *testing.T) {
	_, source, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("locate test source")
	}
	path := filepath.Join(filepath.Dir(source), "../../../../services/mcp-gateway/Sources/App/routes.swift")
	routes, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]bool{
		"GET /health":       true,
		"GET /auth/me":      true,
		"POST /auth/logout": true,
	}
	registrations := regexp.MustCompile(`(?m)^\s*(?:protected|adminProtected)\.(get|post|patch|put|delete)\(([^\n]+)\)\s*\{`)
	segments := regexp.MustCompile(`"([^"]+)"`)
	for _, registration := range registrations.FindAllSubmatch(routes, -1) {
		var parts []string
		for _, segment := range segments.FindAllSubmatch(registration[2], -1) {
			parts = append(parts, string(segment[1]))
		}
		want[strings.ToUpper(string(registration[1]))+" /"+strings.Join(parts, "/")] = true
	}
	if len(want) < 40 {
		t.Fatalf("parsed only %d routes; Gateway route registration format may have changed", len(want))
	}
	names, actual := map[string]bool{}, map[string]bool{}
	for _, operation := range Operations {
		if names[operation.Name] {
			t.Errorf("duplicate command name %q", operation.Name)
		}
		names[operation.Name] = true
		key := operation.Method + " " + operation.Path
		if actual[key] {
			t.Errorf("duplicate operation %s", key)
		}
		actual[key] = true
		if operation.Description == "" {
			t.Errorf("missing description for %s", operation.Name)
		}
		if !want[key] {
			t.Errorf("CLI operation has no canonical management route: %s", key)
		}
	}
	for key := range want {
		if !actual[key] {
			t.Errorf("Gateway management route missing CLI operation: %s", key)
		}
	}
}
