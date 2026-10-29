package cli

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestMyContextCLIBranding(t *testing.T) {
	for _, args := range [][]string{{"version"}, {"help"}} {
		code, out, errs := invoke(t, "", args...)
		if code != 0 || !strings.Contains(out, "MyContextCLI") {
			t.Fatalf("branding: %d %s %s", code, out, errs)
		}
		if args[0] == "help" && (!strings.Contains(out, "Usage: myctx ") || strings.Contains(out, "Usage: context ")) {
			t.Fatal(out)
		}
	}
}
func TestBrandedEnvironmentOverridesLegacy(t *testing.T) {
	for _, key := range []string{"URL", "WEB_URL", "SESSION", "PROFILE", "PROJECT", "CONFIG"} {
		t.Run(key, func(t *testing.T) {
			t.Setenv("CONTEXT_"+key, "legacy")
			t.Setenv("MYCTX_"+key, "branded")
			if value := environment(key); value != "branded" {
				t.Fatal(value)
			}
			t.Setenv("MYCTX_"+key, "")
			if value := environment(key); value != "legacy" {
				t.Fatal(value)
			}
		})
	}
}
func TestConfigRenamePreservesExistingProfiles(t *testing.T) {
	t.Setenv("MYCTX_CONFIG", "")
	t.Setenv("CONTEXT_CONFIG", "")
	root := t.TempDir()
	t.Setenv("HOME", root)
	t.Setenv("APPDATA", filepath.Join(root, "config"))
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(root, "config"))
	dir, err := os.UserConfigDir()
	if err != nil {
		t.Fatal(err)
	}
	primary := filepath.Join(dir, "myctx", "config.json")
	legacy := filepath.Join(dir, "context", "config.json")
	if actual, err := configPath(); err != nil || actual != primary {
		t.Fatalf("new default: %s %v", actual, err)
	}
	c := Config{Profiles: map[string]Profile{"work": {URL: "https://api.example", Session: "retained-session", Project: "retained-project"}}}
	if err = saveConfig(legacy, c); err != nil {
		t.Fatal(err)
	}
	actual, err := configPath()
	if err != nil || actual != legacy {
		t.Fatalf("legacy: %s %v", actual, err)
	}
	loaded, err := loadConfig(actual)
	if err != nil || loaded.Profiles["work"] != c.Profiles["work"] {
		t.Fatalf("profile lost: %v", err)
	}
	if err = saveConfig(primary, Config{}); err != nil {
		t.Fatal(err)
	}
	if actual, err = configPath(); err != nil || actual != primary {
		t.Fatalf("primary priority: %s %v", actual, err)
	}
}
