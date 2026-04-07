# MyContextProtocol

A hosted MCP (Model Context Protocol) gateway that ingests [SKILL.md](https://github.com/cursor-public/skill-creator)-based Agent Skills from a Git repository and exposes them via a stable MCP server endpoint.

**Goal:** Point to a GitHub repo of skills, get `https://{subdomain}.mcp.yourdomain.com` that stays in sync with the repo—with auth, audit logs, and versioned rollouts.

## Overview

- **Input:** Git repos containing one or more skill folders with `SKILL.md` (per Agent Skills standard)
- **Output:** A single MCP endpoint per project serving tools, resources, and prompts derived from those skills
- **MVP:** Skills as data only—no arbitrary code execution from repos

## Tech Stack

| Layer | Choice |
|-------|--------|
| Backend | Vapor (Swift) |
| Database | Supabase Postgres (production); **local file SQLite** via `USE_SQLITE=1` |
| ORM | Fluent + PostgresKit / FluentSQLiteDriver |
| MCP | Custom JSON-RPC handler (no Swift SDK) |
| Parsing | Yams (YAML frontmatter in SKILL.md) |

## Architecture

```
GitHub Repo → Webhook/Poll → Sync Pipeline → Parse SKILL.md → Validate → DB
                                                                          ↓
MCP Client ← JSON-RPC over HTTP ← MCP Endpoint ← Active Release Catalog ←─┘
```

- **Sync pipeline:** Fetches repo tarball at commit SHA, parses `SKILL.md` files, validates against Agent Skills spec, stores releases and skill catalog
- **MCP endpoint:** Serves `tools/list` and `tools/call` from the active release’s catalog
- **Auth:** API keys for MCP clients; user auth (login/session) for admin operations (sync, create-key)

## Quick Start

1. Clone and configure env:

   ```bash
   cp .env.example .env
   # Local SQLite: `USE_SQLITE=1` and leave `DATABASE_URL` / `SUPABASE_DB_URL` empty (creates `db.sqlite`).
   # Postgres: set `USE_SQLITE=0` and `DATABASE_URL=...` or `SUPABASE_DB_URL=...` (recommended).
   # Or set all of `DATABASE_HOST`, `DATABASE_USERNAME`, `DATABASE_PASSWORD`, `DATABASE_NAME` (optional `DATABASE_PORT`).
   # With `APP_ENV=dev` or `APP_ENV=prod`, discrete fields must all be non-empty — there is no silent default to `localhost`/demo creds.
   ```

2. Build and run:

   ```bash
   swift build
   swift run App
   ```

3. Migrations run automatically on startup. For personal use, the seed creates an account from `ADMIN_EMAIL`/`ADMIN_PASSWORD` (default: admin@localhost/admin).

4. **Auth**: `POST /auth/login` with `{"email":"...","password":"..."}` to get a session.

5. **Sync**: `POST /sync` (requires session) triggers repo sync.

6. **Create API key**: `POST /api-keys` (requires session) returns a new MCP API key.

7. **MCP endpoint**: `POST` to `SAAS_MCP_PATH` (default `/mcp`) on the tenant host with `Authorization: Bearer <api_key>` for JSON-RPC: `initialize`, `tools/list`, `tools/call`, `resources/list`, `resources/read`, `prompts/list`, `prompts/get`.
8. **Catalog (dashboard)**: `GET /projects/:id/catalog` (session auth) returns the active release’s tools, resources, and prompts for the UI.

## Environment Variables

| Variable | Description |
|----------|--------------|
| `APP_ENV` | `local`, `dev`, or `prod` (empty/unknown → `prod`, fail closed) |
| `USE_SQLITE` | `1`/`true` for file-backed SQLite; unset/`0` for Postgres |
| `DATABASE_URL` | Postgres connection URL (preferred when not using SQLite) |
| `SUPABASE_DB_URL` | Alternate Postgres URL (read after `DATABASE_URL`) |
| `DATABASE_HOST`, `DATABASE_USERNAME`, `DATABASE_PASSWORD`, `DATABASE_NAME` | Discrete Postgres config when URLs are unset; required (non-empty) for `APP_ENV=dev`/`prod` |
| `DATABASE_PORT` | Postgres port (default `5432`) |
| `DATABASE_INSECURE_TLS` | `1`/`true` to disable TLS cert verification for some managed Postgres setups |
| `ENCRYPTION_KEY` | 32-byte key (base64) for OAuth state and token encryption |
| `GITHUB_TOKEN` | Optional PAT for anonymous/private repo fetch fallbacks |
| `CORS_ORIGIN` / `FRONTEND_URL` | Browser origin and app URL for OAuth and CORS |

See [`.env.example`](.env.example) for the full list used by the API.

## Project Structure

```
Sources/MyContextProtocol/
├── App/           # Configure, bootstrap
├── Controllers/   # Auth, MCP, Webhook
├── Models/        # Fluent models
├── Migrations/    # DB migrations
├── Sync/          # Repo fetcher, SKILL.md parser, validator, pipeline
├── MCP/           # JSON-RPC handler, tool dispatch, API key middleware
├── Middleware/    # Session auth for admin routes
└── Routes/        # Route definitions
```

## Spec & Plan

- Product specs and planning notes live in the team’s internal wiki (not linked here—this repo is open source).
- Implementation plan: see `.cursor/plans/` for phased rollout

## CI/CD

- Backend GitHub Actions + Depot: workflow definitions are in `.github/workflows/`; extended runbooks stay in the team’s internal wiki.

## License

MIT
