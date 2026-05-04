# MyContextProtocol

Service-based monorepo for MyContextProtocol — a hosted MCP gateway that ingests `SKILL.md` files from Git repositories and exposes them through a stable, audited Model Context Protocol endpoint.

## Layout

```
.
├── .depot/workflows/ci.yml          # Backend CI (Depot runners → Docker Hub)
├── .github/workflows/frontend-ci.yml # Frontend CI (GitHub Actions: lint/typecheck/test)
└── services/
    ├── backend/                     # Swift / Vapor 6.2 — see services/backend/README.md
    └── frontend/                    # Next.js 16 / Bun — see services/frontend/README.md
```

Each service is independently buildable with its native toolchain. There is no root-level package manager or workspace orchestration.

## Local development

```bash
# Backend (port 8080 by default)
cd services/backend
swift run App

# Frontend (port 3000 by default; proxies /api/* to NEXT_PUBLIC_API_URL)
cd services/frontend
bun install
bun dev
```

Per-service env files: `services/backend/.env` and `services/frontend/.env`. The frontend's `NEXT_PUBLIC_API_URL` should point at the backend (`http://localhost:8080` for local dev).

## CI / CD

| Pipeline | Trigger | Path filter | Where |
|---|---|---|---|
| Backend CI | push / PR to `main` or `dev` | `services/backend/**` or `.depot/workflows/ci.yml` | Depot runners |
| Frontend CI | push / PR to `main` or `dev` | `services/frontend/**` or `.github/workflows/frontend-ci.yml` | GitHub Actions |

### Deployment

- **Backend** — On push to `dev` / `main`, backend CI builds via Depot and pushes `stygiantech/my-context-protocol:${APP_ENV}` (and a `sha-…` tag) to Docker Hub. Portainer pulls the `${APP_ENV}` tag using `services/backend/docker-compose.yml`.
- **Frontend** — Vercel watches this repo with **Root Directory = `services/frontend`** and reads `services/frontend/vercel.json` for the build command. Required env vars: `NEXT_PUBLIC_API_URL`, `NEXT_PUBLIC_APP_ENV`, `NEXT_PUBLIC_APP_URL`.

## History

The backend retains the original repo history. The frontend was merged in via `git subtree` from `Stygian-Tech/my-context-protocol-frontend@dev`; that repo is archival after cutover.
