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

## Hosted environments

Development and production run on isolated Railway environments with Railway Postgres. See the
root `railway/README.md` and the runbooks under `docs/runbooks/`. The former Fly production app,
Supabase database, and Vercel frontend were permanently removed after the Railway production
cutover and are not rollback resources.

Set production variables on the Railway Gateway service:

```bash
railway variable set --environment production --service Gateway \
  APP_ENV=prod \
  DATABASE_HOST='postgres.railway.internal' \
  DATABASE_PORT=5432 \
  DATABASE_USERNAME='postgres' \
  DATABASE_PASSWORD='...' \
  DATABASE_NAME='railway' \
  ENCRYPTION_KEY='...' \
  CORS_ORIGIN='https://mycontextprotocol.dev' \
  FRONTEND_URL='https://mycontextprotocol.dev' \
  GITHUB_CLIENT_ID='...' \
  GITHUB_CLIENT_SECRET='...' \
  GITHUB_OAUTH_REDIRECT_URI='https://api.mycontextprotocol.dev/auth/github/callback'
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

For tenant custom domains, the gateway creates Railway custom domains after application ownership
verification. Set a production-scoped Railway project token on Gateway:

```bash
railway variable set --environment production --service Gateway \
  RAILWAY_PROJECT_TOKEN='...'
```

The dashboard returns both the application ownership TXT record and Railway's required routing or
ownership records. Without a project token, existing domains keep routing but creating a new tenant
domain fails closed with HTTP 503.

Verified custom domains remain stored when an account loses Pro, but runtime routing requires current Pro entitlement. Routing resumes automatically after the account regains Pro access.

Deploy production from the repository root:

```bash
bash scripts/railway-deploy-production.sh main Gateway
```

GitHub Actions uses the same script on `main` and expects a production-scoped
`RAILWAY_PRODUCTION_TOKEN` repository secret.

### Troubleshooting

Check production deployment logs with:

```bash
railway logs --environment production --service Gateway --deployment --lines 100
```

Common startup failures:

- **Postgres TLS (`CERTIFICATE_VERIFY_FAILED`)** — Railway uses the discrete private-network
  `DATABASE_*` fields documented above and must not also set `DATABASE_URL` or `SUPABASE_DB_URL`.
  For another managed Postgres provider whose CA is not in the container trust store, set
  `DATABASE_SSLROOTCERT_PEM`, `DATABASE_SSLROOTCERT_BASE64`, or a verified file path through
  `DATABASE_SSLROOTCERT`; production rejects disabled certificate verification.
- **Missing database config** — hosted Railway environments require all discrete
  `DATABASE_HOST`, `DATABASE_PORT`, `DATABASE_USERNAME`, `DATABASE_PASSWORD`, and `DATABASE_NAME`
  fields. `USE_SQLITE=1` is only for local file-backed SQLite.

## Docker / Compose

`Dockerfile` builds the Vapor app for container platforms. `docker-compose.yml` remains as an optional Portainer/self-hosting reference and forwards all supported environment variables into the container.

## Internal Docs Boundary

Product specs and the MCP agent guide live in the team’s internal workspace. Do not add Notion URLs or the internal MCP agent guide to this open-source repo without an explicit request.

## License

This service is part of MyContextProtocol and is released under the repository [MIT License](../../LICENSE).
