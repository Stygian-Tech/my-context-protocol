# CI/CD (GitHub Actions)

## Backend (`my-context-protocol`)

- **Workflow:** `.github/workflows/ci.yml`
- **Test:** `swift test` on every push/PR to `main` or `dev`.
- **Docker:** On push to `main` or `dev` only (not on PRs), after tests pass, builds with [Depot](https://depot.dev) and pushes to GHCR.

### Required repository secrets

| Secret | Purpose |
|--------|---------|
| `DEPOT_TOKEN` | Depot API token (or configure OIDC trust in Depot and use `id-token: write` instead). |
| `DEPOT_PROJECT_ID` | Depot project ID (if not using `depot.json` in the repo root). |

Images are tagged `ghcr.io/<owner>/<repo>:sha-<full-sha>` and `ghcr.io/<owner>/<repo>:<branch>` (e.g. `dev`, `main`).

## Frontend (`my-context-protocol-frontend`)

- **Workflow:** `.github/workflows/ci.yml`
- Runs `bun install`, `lint`, `typecheck`, and `test` (Vitest) on `main` and `dev`.

Deploy the test app with **Vercel** pointed at the `dev` branch; set `NEXT_PUBLIC_APP_ENV=dev` and `NEXT_PUBLIC_API_URL` to your deployed API.
