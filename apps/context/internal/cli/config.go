package cli

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"strings"
)

const hostedAPIOrigin = "https://api.mycontextprotocol.dev"

type Profile struct {
	URL     string `json:"url"`
	WebURL  string `json:"web_url,omitempty"`
	Session string `json:"session,omitempty"`
	Project string `json:"project,omitempty"`
}
type Config struct {
	Profiles map[string]Profile `json:"profiles"`
}

func configPath() (string, error) {
	if p := environment("CONFIG"); p != "" {
		return p, nil
	}
	dir, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	primary := filepath.Join(dir, "myctx", "config.json")
	if _, err := os.Stat(primary); err == nil {
		return primary, nil
	} else if !errors.Is(err, os.ErrNotExist) {
		return "", err
	}
	// Keep the existing file authoritative so account profiles and logout remain shared
	// with prior installations instead of copying credentials into divergent stores.
	legacy := filepath.Join(dir, "context", "config.json")
	if _, err := os.Stat(legacy); err == nil {
		return legacy, nil
	} else if !errors.Is(err, os.ErrNotExist) {
		return "", err
	}
	return primary, nil
}
func loadConfig(path string) (Config, error) {
	c := Config{Profiles: map[string]Profile{}}
	b, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return c, nil
	}
	if err != nil {
		return c, err
	}
	if err = json.Unmarshal(b, &c); err != nil {
		return c, fmt.Errorf("invalid config: %w", err)
	}
	if c.Profiles == nil {
		c.Profiles = map[string]Profile{}
	}
	return c, nil
}
func saveConfig(path string, c Config) error {
	b, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return err
	}
	if err = os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return err
	}
	f, err := os.CreateTemp(filepath.Dir(path), ".myctx-*")
	if err != nil {
		return err
	}
	defer os.Remove(f.Name())
	if _, err = f.Write(append(b, '\n')); err != nil {
		f.Close()
		return err
	}
	if err = f.Sync(); err != nil {
		f.Close()
		return err
	}
	if err = f.Close(); err != nil {
		return err
	}
	return os.Rename(f.Name(), path)
}
func validateURL(raw string) (string, error) {
	u, err := url.Parse(raw)
	if err != nil || u.Host == "" || u.User != nil || u.RawQuery != "" || u.Fragment != "" || (u.Path != "" && u.Path != "/") {
		return "", fmt.Errorf("URL must be an API origin without credentials, path, query or fragment")
	}
	if u.Scheme != "https" && !(u.Scheme == "http" && (u.Hostname() == "localhost" || u.Hostname() == "127.0.0.1" || u.Hostname() == "::1")) {
		return "", fmt.Errorf("HTTPS required except for loopback development")
	}
	return strings.TrimSuffix(u.String(), "/"), nil
}

// environment prefers branded settings while retaining existing agent automation.
func environment(key string) string {
	if value := os.Getenv("MYCTX_" + key); value != "" {
		return value
	}
	return os.Getenv("CONTEXT_" + key)
}
