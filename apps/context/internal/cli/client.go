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
	"strings"
	"time"
)

type APIError struct {
	Status int
	Body   json.RawMessage
}

func (e *APIError) Error() string { return fmt.Sprintf("API request failed (HTTP %d)", e.Status) }

type Client struct {
	Origin, Session, WebOrigin string
	HTTP                       *http.Client
}

func newClient(origin, session string, timeout time.Duration) *Client {
	return &Client{Origin: origin, Session: session, HTTP: &http.Client{Timeout: timeout, CheckRedirect: func(_ *http.Request, _ []*http.Request) error { return http.ErrUseLastResponse }}}
}
func (c *Client) request(ctx context.Context, method, path string, query url.Values, body []byte) ([]byte, *http.Response, error) {
	u, err := url.Parse(path)
	if err != nil || !strings.HasPrefix(path, "/") || strings.HasPrefix(path, "//") || u.IsAbs() || u.Host != "" || u.Fragment != "" {
		return nil, nil, fmt.Errorf("API path must be an origin-relative path")
	}
	for k, vs := range query {
		for _, v := range vs {
			q := u.Query()
			q.Add(k, v)
			u.RawQuery = q.Encode()
		}
	}
	req, err := http.NewRequestWithContext(ctx, method, c.Origin+u.String(), bytes.NewReader(body))
	if err != nil {
		return nil, nil, err
	}
	req.Header.Set("Accept", "application/json")
	req.Header.Set("User-Agent", "Context CLI")
	if len(body) > 0 {
		req.Header.Set("Content-Type", "application/json")
	}
	if c.WebOrigin != "" && method != "GET" {
		req.Header.Set("Origin", c.WebOrigin)
	}
	if c.Session != "" {
		req.AddCookie(&http.Cookie{Name: "vapor-session", Value: c.Session})
	}
	resp, err := c.HTTP.Do(req)
	if err != nil {
		var urlErr *url.Error
		if errors.As(err, &urlErr) {
			err = urlErr.Err
		}
		return nil, nil, fmt.Errorf("API request failed: %w", err)
	}
	defer resp.Body.Close()
	b, err := io.ReadAll(io.LimitReader(resp.Body, 32<<20+1))
	if err != nil {
		return nil, resp, err
	}
	if len(b) > 32<<20 {
		return nil, resp, fmt.Errorf("response exceeds 32 MiB")
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		// Redirect targets may carry GitHub installation URLs; return them without following.
		payload := json.RawMessage(b)
		if !json.Valid(payload) {
			payload, _ = json.Marshal(map[string]string{"message": http.StatusText(resp.StatusCode)})
		}
		if resp.StatusCode >= 300 && resp.StatusCode < 400 {
			payload, _ = json.Marshal(map[string]string{"location": resp.Header.Get("Location")})
		}
		return nil, resp, &APIError{resp.StatusCode, payload}
	}
	return b, resp, nil
}
