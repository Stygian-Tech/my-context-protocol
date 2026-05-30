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
  ENCRYPTION_KEY='...' \
  CORS_ORIGIN='https://testing.mycontextprotocol.dev' \
  FRONTEND_URL='https://testing.mycontextprotocol.dev' \
  GITHUB_CLIENT_ID='...' \
  GITHUB_CLIENT_SECRET='...' \
  GITHUB_OAUTH_REDIRECT_URI='https://api.testing.mycontextprotocol.dev/auth/github/callback' \
  --app my-context-protocol-dev-mcp-gateway
```

Include GitHub App, Stripe, SaaS MCP host, and admin/pro bypass secrets as needed from `.env.example`.

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

## Docker / Compose

`Dockerfile` builds the Vapor app for container platforms. `docker-compose.yml` remains as an optional Portainer/self-hosting reference and forwards all supported environment variables into the container.

## Internal Docs Boundary

Product specs and the MCP agent guide live in the team’s internal workspace. Do not add Notion URLs or the internal MCP agent guide to this open-source repo without an explicit request.
