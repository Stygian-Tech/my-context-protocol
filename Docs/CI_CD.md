# CI/CD

## Backend (`my-context-protocol`)

### Workflow location

- **File:** [`.depot/workflows/ci.yml`](../.depot/workflows/ci.yml) (Depot-managed layout in this repo).
- **Runner:** [Depot](https://depot.dev) GitHub Actions runners (`depot-ubuntu-latest`).

### Triggers

| Event | What runs |
|-------|-----------|
| `push` / `pull_request` to `main` or `dev` | Swift **test** job |
| `push` to `main` or `dev` only (not PRs) | **Docker** build & push (after tests pass) |
| `workflow_dispatch` | Tests only (Docker still gated on push to `main`/`dev`) |

Concurrency: one run per ref; newer runs cancel in-progress jobs for the same workflow + ref.

### Test job (`Swift Tests`)

- Installs **Swift 6.2** from swift.org (aligned with `Dockerfile` `swift:6.2-jammy`); avoids older host toolchains that break Linux builds (e.g. dependency availability metadata).
- Runs a **single** `swift test` invocation (see [swiftlang/swift-package-manager#9441](https://github.com/swiftlang/swift-package-manager/issues/9441) — a second SwiftPM pass can hang at “Planning build” on Linux).
- **Vapor / Swift Testing:** CI patches Vapor’s checkout so `VaporTesting` resolves `swift-testing` on Linux (see [vapor/vapor#3391](https://github.com/vapor/vapor/issues/3391) and [`scripts/README.md`](../scripts/README.md)).
- **DB:** Test step clears `DATABASE_URL` / `SUPABASE_DB_URL` so `configure` does not point tests at Postgres unexpectedly.
- On failure, uploads `.build/ci-logs/` as artifact `swift-test-diagnostics`.

### Docker job (`Docker Build and Push`)

- **Registry:** [Docker Hub](https://hub.docker.com/) — image `stygiantech/my-context-protocol`.
- **Tags:**
  - `stygiantech/my-context-protocol:prod` — push to **`main`**
  - `stygiantech/my-context-protocol:dev` — push to **`dev`**
  - `stygiantech/my-context-protocol:sha-<full-git-sha>` — every qualifying push
- **Build:** [Depot](https://depot.dev) remote build (`depot/build-push-action`); context is repo root (`Dockerfile` at root).

### Depot auth (Docker job)

- **OIDC (default in workflow):** Trust relationship in Depot for this GitHub repo + job `permissions: contents: read` and `id-token: write`. No `DEPOT_TOKEN` secret. Project ID is set on `depot/build-push-action` as `project:` (public identifier).
- **Token fallback:** If not using OIDC, set `DEPOT_TOKEN` in GitHub secrets and add `token:` to `depot/build-push-action` per [Depot authentication](https://depot.dev/docs/cli/authentication).

### Required GitHub repository secrets (Docker job)

| Secret | Purpose |
|--------|---------|
| `DOCKERHUB_USERNAME` | `docker login` before push to Docker Hub. |
| `DOCKERHUB_TOKEN` | Docker Hub access token or password for CI. |

Depot-only secrets are **not** required when OIDC is configured.

**Depot dashboard “environment variables”** do **not** automatically appear inside `docker build`. Pass build-time values with `build-args` / `secrets` on `depot/build-push-action` if the `Dockerfile` needs them (see comments in the workflow).

---

## Frontend (`my-context-protocol-frontend`)

- **Deploy:** Typically **[Vercel](https://vercel.com)** connected to the GitHub repo (e.g. production from `main`, previews from `dev` / PRs). This workspace does not include a GitHub Actions workflow file; CI may live entirely on Vercel or in another path on the remote repo.
- **Env:** Set `NEXT_PUBLIC_API_URL` (and optional `NEXT_PUBLIC_APP_URL`) in the Vercel project. See the frontend `README.md` for **Vercel Web Analytics** (`@vercel/analytics`) and enabling Web Analytics in the dashboard.

---

## Related docs

| Doc | Topic |
|-----|--------|
| [`scripts/README.md`](../scripts/README.md) | Local / CI Vapor `swift-testing` patch |
| [`Dockerfile`](../Dockerfile) | Release image build |
| Frontend `README.md` | Bun, Vercel env, analytics |
