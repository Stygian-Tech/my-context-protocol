# MyContextProtocol

Stygian-style monorepo for MyContextProtocol: a hosted MCP gateway that ingests `SKILL.md` files from Git repositories, compiles them into policy-aware MCP capabilities, and exposes them through stable audited endpoints.

## Layout

```text
.
├── apps/
│   └── web/                         # Next.js 16 / Bun dashboard
├── packages/
│   ├── mycontext-api-contract/      # Backend API contract docs
│   └── mycontext-web-client/        # Shared frontend/API-facing TypeScript types
├── services/
│   └── mcp-gateway/                 # Swift / Vapor MCP gateway
├── docs/
│   ├── architecture/
│   └── test-plans/
├── scripts/                         # Local CI and deploy entrypoints
├── package.json                     # Bun workspaces + Turbo
└── turbo.json
```

The backend also consumes the external Swift package `mcp-server-kit` for reusable MCP protocol primitives. During local two-repo development this is wired as a sibling checkout; publish and pin that package before relying on GitHub Actions or Fly remote builds.

## Local Development

```bash
# Install all Bun workspace dependencies
bun install

# Backend (port 8080 by default)
cd services/mcp-gateway
cp .env.example .env
swift run App

# Frontend (port 3000 by default)
cd ../../apps/web
cp .env.example .env
bun dev
```

Set the frontend `NEXT_PUBLIC_API_URL` to the backend origin, usually `http://localhost:8080`.

## CI / CD

GitHub Actions is the source of truth for CI. The single workflow at `.github/workflows/ci.yml` calls local scripts so checks can be reproduced outside Actions:

```bash
bash scripts/ci.sh
```

The workflow detects changes with `scripts/ci-detect-changes.sh`, runs the Bun/Turbo workspace checks, runs Swift tests/builds for `services/mcp-gateway`, and conditionally deploys the gateway to Fly.io on `dev` and `main`.

### Deployment

- **Backend**: Fly.io, configured by `services/mcp-gateway/fly.toml` and deployed with `bash scripts/fly-deploy-mcp-gateway.sh dev|main`.
- **Frontend**: Vercel Git integration with **Root Directory = `apps/web`**. Vercel reads `apps/web/vercel.json`.
- **Optional self-hosting**: `services/mcp-gateway/docker-compose.yml` remains as a Portainer/Compose reference, but Fly is the primary backend path.

## History

The backend retains the original repo history. The frontend was merged in via `git subtree` from `Stygian-Tech/my-context-protocol-frontend@dev`; that repo is archival after cutover.
