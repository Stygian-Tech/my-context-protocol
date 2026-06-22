# MyContextProtocol MCP Gateway

Swift/Vapor backend for MyContextProtocol. It syncs Git repositories containing `SKILL.md` files, compiles releases into MCP tools/resources/prompts, and serves the tenant MCP endpoint plus dashboard REST APIs.

## Stack

- Swift 6 / Vapor
- Fluent with Postgres in hosted environments and SQLite for local development/tests
- GitHub OAuth and GitHub App installation flows
- Stripe billing webhooks
- `mcp-server-kit` for reusable MCP protocol models and schema primitives

## Local Development

```bash
cp .env.example .env
swift run App
```

By default the app listens on `0.0.0.0:8080`. For local SQLite, set `USE_SQLITE=1` and leave `DATABASE_URL` / `SUPABASE_DB_URL` empty. For hosted-like local development, set `APP_ENV=dev` plus `DATABASE_URL` or `SUPABASE_DB_URL`.

## Tests

```bash
swift test --enable-swift-testing --disable-xctest --no-parallel -Xswiftc -warnings-as-errors
swift build -c release --product App -Xswiftc -warnings-as-errors
```

Tests clear inherited hosted database URLs and fall back to in-memory SQLite unless explicitly configured to use Postgres.

## Structure

```text
Sources/App/
├── Controllers/   # Auth, MCP, billing, projects, admin, webhooks
├── MCP/           # Product-specific MCP catalog, OAuth, notifications, handlers
├── Middleware/    # Tenant host, auth, rate limits, origin checks
├── Migrations/    # Fluent schema migrations
├── Models/        # Fluent models
├── Services/      # App services and environment helpers
├── Sync/          # Git fetch, SKILL parsing, validation, compilation
└── Utilities/     # Shared low-level helpers
```

## Fly.io

First-time setup:

```bash
fly apps create my-context-protocol-dev-mcp-gateway
fly apps create my-context-protocol-prod-mcp-gateway
```

Set secrets on each Fly app:

```bash
fly secrets set \
  APP_ENV=dev \
  DATABASE_URL='postgres://...' \
  DATABASE_INSECURE_TLS=1 \
  ENCRYPTION_KEY='...' \
  CORS_ORIGIN='https://testing.mycontextprotocol.dev' \
  FRONTEND_URL='https://testing.mycontextprotocol.dev' \
  GITHUB_CLIENT_ID='...' \
  GITHUB_CLIENT_SECRET='...' \
  GITHUB_OAUTH_REDIRECT_URI='https://api.testing.mycontextprotocol.dev/auth/github/callback' \
  --app my-context-protocol-dev-mcp-gateway
```

`DATABASE_INSECURE_TLS=1` is for dev only. Production rejects disabled Postgres certificate verification.

`GITHUB_OAUTH_REDIRECT_URI` is **only** for dashboard GitHub login (`/auth/github/callback`). Do not point it at `/auth/github/app/callback` — that path is for GitHub App installation and uses `GITHUB_APP_SETUP_CALLBACK_URL` instead. If login OAuth is sent to the app callback, users return to the frontend with `github_app_error=invalid_state` and `/auth/me` stays 401.

Include GitHub App, Stripe, SaaS MCP host, and admin/pro bypass secrets as needed from `.env.example`.

## MCP OAuth

Tenant MCP OAuth is designed for Claude-compatible public clients:

- Dynamic client registration accepts public clients only (`token_endpoint_auth_method=none`).
- The only supported grant is `authorization_code` with PKCE (`S256`).
- Public DCR does not issue `client_secret` values.
- `client_credentials` and `refresh_token` are not supported by the public OAuth surface.

Claude Code should be added with the project MCP URL, for example:

```bash
claude mcp add --transport http my-context https://<project-host>/mcp
```

Use Claude's fixed callback-port option only when you need a stable localhost redirect URI for local testing.

For tenant custom domains, the gateway must create Fly edge certificates after DNS verification. Set a Fly token with certificate access and the gateway app name:

```bash
fly secrets set \
  FLY_API_TOKEN='FlyV1...' \
  FLY_CERTIFICATE_APP_NAME='my-context-protocol-dev-gateway' \
  FLY_CERTIFICATE_OWNERSHIP_TXT_VALUE='app-12qq5w0' \
  --app my-context-protocol-dev-gateway
```

Use the value Fly shows for `TXT _fly-ownership.<hostname>` when running `fly certs setup <hostname>`.
The dashboard includes that ownership TXT record in the tenant DNS validation flow before requesting a Fly certificate.

Tenant DNS setup uses two TXT records plus one routing option:

- `TXT _mcp-verify.<hostname>` proves project ownership to MyContextProtocol.
- `TXT _fly-ownership.<hostname>` proves hostname ownership to Fly so the gateway can provision an edge certificate.
- Routing can use either Fly-provided A/AAAA records or the Fly-provided CNAME target. Do not configure A/AAAA and CNAME records for the same hostname; DNS providers reject that combination.

Without these runtime secrets, tenant DNS can route to Fly, but TLS for that custom hostname will fail before Vapor sees the request.

Verified custom domains remain stored when an account loses Pro, but runtime routing requires current Pro entitlement. Routing resumes automatically after the account regains Pro access.

Deploy:

```bash
bash deploy.sh dev
bash deploy.sh main
```

From the repo root:

```bash
bash scripts/fly-deploy-mcp-gateway.sh dev
```

GitHub Actions uses the root script and expects `FLY_API_TOKEN`, plus optional `FLY_MCP_GATEWAY_APP_DEV`, `FLY_MCP_GATEWAY_APP_PROD`, and `FLY_ORG` secrets.

### Troubleshooting

If Fly reports the app is not listening on `0.0.0.0:8080`, check machine logs:

```bash
fly logs -a my-context-protocol-dev-gateway
```

Common startup failures:

- **Postgres TLS (`CERTIFICATE_VERIFY_FAILED`)** — for dev only, deploys can set `DATABASE_INSECURE_TLS=1`. Production rejects disabled certificate verification. For Supabase or another managed Postgres provider whose CA is not in the container OS trust store, download the provider database CA bundle and set it as a secret using one of `DATABASE_SSLROOTCERT_PEM`, `DATABASE_SSLROOTCERT_BASE64`, or a file path in `DATABASE_SSLROOTCERT` / URL `sslrootcert=/path`; verification and hostname checks stay enabled.
- **Missing database config** — `APP_ENV=dev` requires `DATABASE_URL` or `SUPABASE_DB_URL` (or all discrete `DATABASE_*` fields). `USE_SQLITE=1` is for local file SQLite only, not Fly.

## Docker / Compose

`Dockerfile` builds the Vapor app for container platforms. `docker-compose.yml` remains as an optional Portainer/self-hosting reference and forwards all supported environment variables into the container.

## Internal Docs Boundary

Product specs and the MCP agent guide live in the team’s internal workspace. Do not add Notion URLs or the internal MCP agent guide to this open-source repo without an explicit request.

## License

This service is part of MyContextProtocol and is released under the repository [MIT License](../../LICENSE).
