# Context

Context is the Go CLI for MyContextProtocol. It exposes every current account,
project, and administrator management route to people and agents. Success output
is JSON on stdout; errors are JSON on stderr. It uses only the Go standard library.

## Install

Requires Go 1.23 or newer. From this repository:

```sh
cd apps/context
make install                     # installs context into GOBIN or GOPATH/bin
# Or: make build                 # produces bin/context
context version
```

Build a versioned binary with `make build VERSION=0.1.0`. Cross compilation uses
normal Go tooling, for example `GOOS=linux GOARCH=amd64 go build -o bin/context-linux-amd64 ./cmd/context`.
No Node or Swift runtime is needed to run the CLI.

## Authenticate

Use the gateway/API origin, not a tenant MCP endpoint or the dashboard origin:

```sh
context config set --url https://YOUR_GATEWAY_ORIGIN
context auth login
context auth status
```

Login opens GitHub in your browser. Context binds an ephemeral port on
`127.0.0.1`, validates a random callback nonce, exchanges the single-use handoff,
and stores the account session in your local config file. `--no-browser` prints
the login URL for manual opening on the same machine. Login expires after five
minutes; Ctrl-C cancels. Browser login requires the gateway's `/auth/cli/github`
route included in this change. Until that gateway version is deployed, use
session import instead.

The gateway supplies its configured frontend origin during login so subsequent
mutations satisfy the existing CSRF policy. Older gateways/session imports need
`--web-url https://YOUR_DASHBOARD_ORIGIN` or `CONTEXT_WEB_URL`.

For an existing account session:

```sh
# Pipe the raw vapor-session cookie value from a secure credential source:
credential-source | context auth login --session-stdin --web-url https://YOUR_DASHBOARD_ORIGIN
```

For ephemeral agent/CI authentication, inject `CONTEXT_SESSION`, `CONTEXT_URL`,
and `CONTEXT_WEB_URL` from a secret manager. A project MCP API key is not an
account administration credential. Context does not read stdin unless explicitly
requested with `--session-stdin` or `--data -`. It never asks interactive questions.
`auth logout` revokes the active session and removes the stored credential;
unset `CONTEXT_SESSION` separately if you provided it through the environment.

Config lives at the platform user-config directory under `context/config.json`
(macOS: `~/Library/Application Support/context/config.json`). `--config FILE` or
`CONTEXT_CONFIG` overrides it. New directories use mode 0700 and files mode 0600
on Unix. Sessions are plaintext in this private file; use environment injection
when persistence is undesirable. Config writes are atomic. Concurrent writes to
the same config file are not supported.

## Profiles and defaults

```sh
context --profile development config set --url http://localhost:8080 --web-url http://localhost:3000
context --profile development auth login
context --profile development config set --project PROJECT_UUID
context --profile development projects get
context config show
```

Flags take precedence over environment variables, which take precedence over the
selected profile. Profile defaults to `default` (`CONTEXT_PROFILE` overrides it).
`--id` overrides `--project`, then `CONTEXT_PROJECT`, then the stored project.
Credentials and project defaults are scoped to the API origin. Changing a
profile's URL clears its stored session and project. `config show` reports whether
a credential is present without exposing its value.

## Agent discovery and requests

```sh
context help
context projects --help
context commands                  # JSON operation name/method/path/description registry
context api operations            # same registry
context projects list --compact
context projects create --data '{"name":"My Skills","slug":"my-skills"}'
context projects update --id PROJECT_UUID --set 'name="Shared Skills"'
context repos connect --id PROJECT_UUID --data '{"owner":"example","repo":"skills","branch":"main"}'
context projects sync --id PROJECT_UUID
context releases list --id PROJECT_UUID
context releases validation --id PROJECT_UUID --release-id RELEASE_UUID
context releases activate --id PROJECT_UUID --release-id RELEASE_UUID
context skills list --id PROJECT_UUID --release-id RELEASE_UUID
context runtime update --id PROJECT_UUID --data @runtime-settings.json
context logs list --id PROJECT_UUID --query limit=100 --query offset=0
context skills usage --id PROJECT_UUID --query page=1 --query page_size=100
```

Flags can appear before or after command words. All response fields and server
validation errors are preserved, including exact JSON integers. Empty successful
responses emit `{"ok":true}`. Non-JSON responses become `{"result":"..."}`.
There are no automatic retries: mutations run once. Set `--timeout 60s` to override
the default 30-second HTTP timeout. Responses are bounded to 32 MiB and request
files/stdin to 8 MiB. Lists follow server pagination: logs use `limit` and `offset`;
skill usage uses `page` and `page_size`. The CLI returns one page per invocation.

Use `--data` for a JSON literal, `--data @file.json` for a file, or `--data -` for
stdin. Repeated `--set field=JSON` merges top-level fields into an object; strings
must be JSON-quoted. Repeated `--query key=value` adds query parameters. Existing
backend schemas govern payload validation; complex runtime/skill payloads can be
passed unchanged from files. No private fields are removed from successful API
responses: API-key creation intentionally returns the secret once.

| Group | Commands |
| --- | --- |
| `auth` | `login`, `status`, `me`, `logout` |
| `dashboard` | `summary`, `timeseries` |
| `projects` | `list`, `create`, `get`, `update`, `set-active`, `summary`, `timeseries`, `sync` |
| `catalog` | `get`, `update` |
| `repos` | `connection`, `connect` |
| `releases` | `list`, `activate`, `validation` |
| `skills` | `list`, `update`, `writeback`, `usage` |
| `runtime` | `get`, `update` |
| `keys` | `list`, `create`, `update`, `revoke` |
| `logs` | `list` |
| `domains` | `get`, `set`, `verify` |
| `billing` | `checkout`, `portal` |
| `github` | `repos`, `install` |
| `admin` | `metrics`, `timeseries`, `rollup-refresh`, `lookup`, `privileged-accounts`, `account-flags` |

Project commands use `--id` (or default project). Release commands additionally
use `--release-id`; skill modifications use `--compiled-skill-id`; key update and
revoke use `--key-id`. GitHub App installation uses `--query project_id=PROJECT_UUID`.
Administrator operations retain the server's privilege checks.

Common payloads:

| Operation | JSON body |
| --- | --- |
| `projects create` | `{"name":"Skills","slug":"skills"}` |
| `projects update` | `{"name":"New Name"}` |
| `catalog update` | `{"markdown":"# Skills"}` (empty markdown resets) |
| `repos connect` | `{"owner":"org","repo":"skills","branch":"main"}` |
| `keys create` / `keys update` | `{"name":"Agent"}` |
| `domains set` | `{"hostname":"context.example.com"}` |
| `billing checkout` | `{"interval":"month"}` or `{"interval":"year"}` |
| `admin lookup` | `{"github_login":"example"}` (also `github_id` or `email`) |
| `admin account-flags` | `{"account_id":"UUID","is_admin":false,"paywall_bypass":true}` |

`skills writeback` creates an external branch and draft pull request; invoking
that command authorizes that action. Billing commands create URLs; they do not
open or complete checkout. GitHub installation returns its browser URL. HTTP
redirects are never followed with account credentials.

For API operations beyond the named registry:

```sh
context api GET /projects
context api PATCH /projects/PROJECT_UUID --data @project.json
```

Raw requests stay on the configured API origin. This is an application control
CLI; tenant MCP protocol calls, inbound webhooks, internal infrastructure routes,
and browser callback endpoints are not named management commands. Agent shells
can run this CLI directly; it does not require a model-provider account.

Exit codes: `0` success, `1` transport/server error, `2` invalid arguments,
`3` HTTP 401, `4` HTTP 403, `130` interrupted. Error JSON includes `code`, `error`,
and, for HTTP errors, `status` and original JSON `details`.

## Development

```sh
make check
make test
make build
```

The route-coverage test reads `services/mcp-gateway/Sources/App/routes.swift` and
fails when a management endpoint is missing from the registry. Tests therefore
run from the monorepo checkout. The root CI script runs Go format, vet, race tests,
and build alongside existing Web and Swift checks.
