package cli

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"sort"
	"strings"
	"time"
)

type options map[string][]string

func (o options) get(k string) string {
	v := o[k]
	if len(v) > 0 {
		return v[len(v)-1]
	}
	return ""
}
func parse(args []string) ([]string, options, error) {
	var words []string
	o := options{}
	bools := map[string]bool{"help": true, "version": true, "no-browser": true, "session-stdin": true, "compact": true}
	allowed := map[string]bool{"url": true, "web-url": true, "profile": true, "config": true, "project": true, "id": true, "release-id": true, "compiled-skill-id": true, "key-id": true, "data": true, "query": true, "set": true, "timeout": true}
	for i := 0; i < len(args); i++ {
		a := args[i]
		if a == "-h" {
			a = "--help"
		}
		if !strings.HasPrefix(a, "--") {
			words = append(words, a)
			continue
		}
		k, v, has := strings.Cut(strings.TrimPrefix(a, "--"), "=")
		if bools[k] {
			if has {
				return nil, nil, fmt.Errorf("--%s does not take a value", k)
			}
			o[k] = []string{"true"}
			continue
		}
		if !allowed[k] {
			return nil, nil, fmt.Errorf("unknown flag --%s", k)
		}
		if !has {
			i++
			if i >= len(args) {
				return nil, nil, fmt.Errorf("--%s requires a value", k)
			}
			v = args[i]
		}
		if k != "query" && k != "set" && len(o[k]) > 0 {
			return nil, nil, fmt.Errorf("--%s may only be specified once", k)
		}
		o[k] = append(o[k], v)
	}
	return words, o, nil
}

// Main writes JSON results to stdout and JSON errors to stderr. It never prompts on stdin.
func Main(ctx context.Context, args []string, in io.Reader, out, errOut io.Writer, version string) int {
	err := run(ctx, args, in, out, errOut, version)
	if err == nil {
		return 0
	}
	code := 1
	payload := map[string]any{"error": err.Error(), "code": "request_failed"}
	var api *APIError
	if errors.As(err, &api) {
		payload["status"] = api.Status
		payload["details"] = api.Body
		if api.Status == 401 {
			code = 3
			payload["code"] = "unauthenticated"
		} else if api.Status == 403 {
			code = 4
			payload["code"] = "forbidden"
		}
	}
	var usage *usageError
	if errors.As(err, &usage) {
		code = 2
		payload["code"] = "invalid_arguments"
	}
	if errors.Is(err, context.Canceled) {
		code = 130
		payload["code"] = "canceled"
	}
	_ = json.NewEncoder(errOut).Encode(payload)
	return code
}

type usageError struct{ error }

func usage(format string, args ...any) error { return &usageError{fmt.Errorf(format, args...)} }
func emit(out io.Writer, b []byte, compact bool) error {
	if len(b) == 0 {
		b = []byte(`{"ok":true}`)
	}
	if !json.Valid(b) {
		b, _ = json.Marshal(map[string]string{"result": string(b)})
	}
	var v any
	if err := decodeJSON(b, &v); err != nil {
		return err
	}
	enc := json.NewEncoder(out)
	if !compact {
		enc.SetIndent("", "  ")
	}
	return enc.Encode(v)
}
func encode(out io.Writer, v any) error { return json.NewEncoder(out).Encode(v) }
func help(out io.Writer, words []string) error {
	fmt.Fprintln(out, "MyContextCLI — agent-friendly MyContextProtocol CLI\n\nUsage: myctx <group> <command> [flags]\nHosted service: api.mycontextprotocol.dev (override with --url for self-hosting)\n\nAuthentication: auth login [--no-browser] | auth login --session-stdin | auth status | auth logout\nConfiguration: config show | config set --url ORIGIN [--project ID]\nDiscovery: commands (JSON) | api operations (JSON) | help\nRaw API: api METHOD /path [--data JSON|@file|-] [--query key=value]\n\nGlobal flags: --url ORIGIN --web-url ORIGIN --profile NAME --config FILE --project ID --timeout 30s --compact\nRequest flags: --id ID --release-id ID --compiled-skill-id ID --key-id ID\n               --data JSON|@file|- --set field=JSON --query key=value (repeatable)\nEnvironment: MYCTX_URL, MYCTX_WEB_URL, MYCTX_SESSION, MYCTX_PROFILE, MYCTX_CONFIG, MYCTX_PROJECT (legacy CONTEXT_* also supported)\n\nCommands:")
	if len(words) > 0 && words[0] == "help" {
		words = words[1:]
	}
	prefix := strings.Join(words, " ")
	groups := make(map[string][]Operation)
	var groupOrder []string
	for _, op := range Operations {
		if prefix != "" && op.Name != prefix && !strings.HasPrefix(op.Name, prefix+" ") {
			continue
		}
		group, _, _ := strings.Cut(op.Name, " ")
		if len(groups[group]) == 0 {
			groupOrder = append(groupOrder, group)
		}
		groups[group] = append(groups[group], op)
	}
	for i, group := range groupOrder {
		if i > 0 {
			fmt.Fprintln(out)
		}
		for _, op := range groups[group] {
			fmt.Fprintf(out, "  %-28s %s\n", op.Name, op.Description)
		}
	}
	return nil
}
func run(ctx context.Context, args []string, in io.Reader, out, errOut io.Writer, version string) error {
	words, o, err := parse(args)
	if err != nil {
		return usage("%v", err)
	}
	name := strings.Join(words, " ")
	if o.get("version") != "" || name == "version" {
		return encode(out, map[string]string{"name": "MyContextCLI", "version": version})
	}
	if o.get("help") != "" || name == "" || (len(words) > 0 && words[0] == "help") {
		return help(out, words)
	}
	if name == "commands" || name == "api operations" {
		return encode(out, Operations)
	}
	timeout := 30 * time.Second
	if s := o.get("timeout"); s != "" {
		timeout, err = time.ParseDuration(s)
		if err != nil || timeout <= 0 {
			return usage("--timeout must be a positive duration")
		}
	}
	path := o.get("config")
	if path == "" {
		path, err = configPath()
		if err != nil {
			return err
		}
	}
	c, err := loadConfig(path)
	if err != nil {
		return err
	}
	profileName := o.get("profile")
	if profileName == "" {
		profileName = environment("PROFILE")
	}
	if profileName == "" {
		profileName = "default"
	}
	p := c.Profiles[profileName]
	origin := o.get("url")
	if origin == "" {
		origin = environment("URL")
	}
	if origin == "" {
		origin = p.URL
	}
	if origin == "" {
		origin = hostedAPIOrigin
	}
	if name == "config show" {
		return encode(out, map[string]any{"profile": profileName, "url": origin, "web_url": p.WebURL, "project": p.Project, "authenticated": p.Session != "" || environment("SESSION") != "", "config": path})
	}
	origin, err = validateURL(origin)
	if err != nil {
		return usage("%v", err)
	}
	if name == "config set" {
		if p.URL != "" && p.URL != origin {
			p.Session = ""
			p.Project = ""
			p.WebURL = ""
		}
		p.URL = origin
		if v := o.get("web-url"); v != "" {
			p.WebURL, err = validateURL(v)
			if err != nil {
				return usage("invalid --web-url: %v", err)
			}
		}
		if v := o.get("project"); v != "" {
			p.Project = v
		}
		c.Profiles[profileName] = p
		if err = saveConfig(path, c); err != nil {
			return err
		}
		return encode(out, map[string]bool{"ok": true})
	}
	session := environment("SESSION")
	if session == "" && p.URL == origin {
		session = p.Session
	}
	client := newClient(origin, session, timeout)
	webURL := o.get("web-url")
	if webURL == "" {
		webURL = environment("WEB_URL")
	}
	if webURL == "" && p.URL == origin {
		webURL = p.WebURL
	}
	if webURL != "" {
		client.WebOrigin, err = validateURL(webURL)
		if err != nil {
			return usage("invalid frontend origin: %v", err)
		}
	}
	if name == "auth login" {
		var credential string
		if o.get("session-stdin") != "" {
			raw, e := io.ReadAll(io.LimitReader(in, 8193))
			if e != nil {
				return e
			}
			credential = strings.TrimSpace(string(raw))
			if len(raw) > 8192 || credential == "" || strings.ContainsAny(credential, "\r\n;\x00") {
				return usage("stdin must contain a single session cookie value")
			}
			client.Session = credential
			if _, _, err = client.request(ctx, "GET", "/auth/me", nil, nil); err != nil {
				return err
			}
		} else {
			credential, err = browserLogin(ctx, client, o.get("no-browser") != "", errOut)
			if err != nil {
				return err
			}
		}
		if p.URL != origin {
			p.Project = ""
		}
		p.URL = origin
		p.WebURL = client.WebOrigin
		p.Session = credential
		c.Profiles[profileName] = p
		if err = saveConfig(path, c); err != nil {
			return err
		}
		return encode(out, map[string]any{"ok": true, "profile": profileName})
	}
	if name == "auth logout" {
		if session != "" {
			if _, _, err = client.request(ctx, "POST", "/auth/logout", nil, nil); err != nil {
				var e *APIError
				if !errors.As(err, &e) || e.Status != 401 {
					return err
				}
			}
		}
		if p.URL == origin {
			p.Session = ""
			c.Profiles[profileName] = p
			if err = saveConfig(path, c); err != nil {
				return err
			}
		}
		return encode(out, map[string]bool{"ok": true})
	}
	if name == "auth status" {
		name = "auth me"
	}
	var method, route string
	if len(words) >= 1 && words[0] == "api" {
		if len(words) != 3 {
			return usage("usage: myctx api METHOD /path")
		}
		method = strings.ToUpper(words[1])
		route = words[2]
		if method != "GET" && method != "POST" && method != "PATCH" && method != "PUT" && method != "DELETE" {
			return usage("unsupported HTTP method")
		}
	} else {
		for _, op := range Operations {
			if op.Name == name {
				method = op.Method
				route = op.Path
				break
			}
		}
		if route == "" {
			return usage("unknown command %q; run myctx help", name)
		}
	}
	project := o.get("id")
	if project == "" {
		project = o.get("project")
	}
	if project == "" {
		project = environment("PROJECT")
	}
	if project == "" && p.URL == origin {
		project = p.Project
	}
	replacements := map[string]string{"id": project, "releaseId": o.get("release-id"), "compiledSkillId": o.get("compiled-skill-id"), "keyId": o.get("key-id")}
	for _, segment := range strings.Split(route, "/") {
		if strings.HasPrefix(segment, ":") {
			key := segment[1:]
			v := replacements[key]
			if v == "" {
				return usage("missing path parameter %s; see myctx help", key)
			}
			if v == "." || v == ".." || strings.ContainsAny(v, "/\\?#%") {
				return usage("invalid path parameter %s", key)
			}
			route = strings.ReplaceAll(route, segment, url.PathEscape(v))
		}
	}
	query := url.Values{}
	for _, s := range o["query"] {
		k, v, ok := strings.Cut(s, "=")
		if !ok || k == "" {
			return usage("--query requires key=value")
		}
		query.Add(k, v)
	}
	body, err := requestBody(o, in)
	if err != nil {
		return usage("%v", err)
	}
	if (method == http.MethodGet || method == http.MethodDelete) && len(body) > 0 {
		return usage("%s does not accept --data or --set", method)
	}
	b, resp, err := client.request(ctx, method, route, query, body)
	// Install URLs are intentionally returned to the agent, never followed with credentials.
	if resp != nil && name == "github install" && resp.StatusCode >= 300 && resp.StatusCode < 400 {
		return encode(out, map[string]string{"url": resp.Header.Get("Location")})
	}
	if err != nil {
		return err
	}
	return emit(out, b, o.get("compact") != "")
}
func requestBody(o options, in io.Reader) ([]byte, error) {
	var b []byte
	var err error
	if s := o.get("data"); s != "" {
		switch {
		case s == "-":
			b, err = io.ReadAll(io.LimitReader(in, 8<<20+1))
		case strings.HasPrefix(s, "@"):
			var f *os.File
			f, err = os.Open(s[1:])
			if err == nil {
				defer f.Close()
				b, err = io.ReadAll(io.LimitReader(f, 8<<20+1))
			}
		default:
			b = []byte(s)
		}
		if err != nil {
			return nil, err
		}
		if len(b) > 8<<20 {
			return nil, fmt.Errorf("request exceeds 8 MiB")
		}
		if !json.Valid(b) {
			return nil, fmt.Errorf("--data must contain valid JSON")
		}
	}
	if len(o["set"]) > 0 {
		obj := map[string]any{}
		if len(b) > 0 {
			if err = decodeJSON(b, &obj); err != nil || obj == nil {
				return nil, fmt.Errorf("--set requires an object body")
			}
		}
		// Stable application order lets a later --set override an earlier one.
		for _, s := range o["set"] {
			k, v, ok := strings.Cut(s, "=")
			if !ok || k == "" {
				return nil, fmt.Errorf("--set requires field=JSON")
			}
			var value any
			if err = decodeJSON([]byte(v), &value); err != nil {
				return nil, fmt.Errorf("--set %s must be valid JSON (quote strings)", k)
			}
			obj[k] = value
		}
		b, err = json.Marshal(obj)
	}
	return b, err
}

// SortedOperationNames is also useful to shell completion generators.
func SortedOperationNames() []string {
	names := make([]string, 0, len(Operations))
	for _, op := range Operations {
		names = append(names, op.Name)
	}
	sort.Strings(names)
	return names
}

func decodeJSON(b []byte, target any) error {
	if !json.Valid(b) {
		return fmt.Errorf("invalid JSON")
	}
	d := json.NewDecoder(bytes.NewReader(b))
	d.UseNumber()
	return d.Decode(target)
}
