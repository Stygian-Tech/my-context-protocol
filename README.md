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
| Database | Supabase Postgres |
| ORM | Fluent + PostgresKit |
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
   cp Resources/env.example .env
   # Edit .env with DATABASE_URL (or individual DB vars), GITHUB_TOKEN, GITHUB_REPO, etc.
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

7. **MCP endpoint**: `POST /mcp` with `Authorization: Bearer <api_key>` for JSON-RPC (initialize, tools/list, tools/call).

## Environment Variables

| Variable | Description |
|----------|--------------|
| `SUPABASE_URL` | Postgres connection URL |
| `SUPABASE_SERVICE_KEY` | Service role key |
| `GITHUB_TOKEN` | PAT for private repos |
| `GITHUB_REPO` | `owner/repo` |
| `GITHUB_BRANCH` | Branch to sync (default: `main`) |
| `PROJECT_SLUG` | Project identifier |
| `WEBHOOK_SECRET` | GitHub webhook signature verification |
| `JWT_SECRET` | For session/JWT signing |

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

- [Notion spec](https://www.notion.so/MyContextProtocol-325f6c1638ed80568b93dc8e6abba384)
- Implementation plan: see `.cursor/plans/` for phased rollout

## License

MIT
