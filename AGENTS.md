## Learned User Preferences

- When committing on this repo, keep unrelated local changes out of the commit and honor an explicitly provided staged-file list as authoritative.

## Learned Workspace Facts

- The repository is organized as a Stygian-style Bun/Turbo monorepo: `apps/web` for the Next.js dashboard, `services/mcp-gateway` for the Swift/Vapor backend, and `packages/*` for shared contracts/types.
- Backend code lives under `services/mcp-gateway/Sources/App`; stale references to `Sources/MyContextProtocol`, `services/backend`, or `services/frontend` should be corrected when touched.
- Frontend deployment is Vercel-based with root directory `apps/web`; backend deployment is Fly.io-based with config in `services/mcp-gateway/fly.toml`.
- CI is designed to run on GitHub Actions through `.github/workflows/ci.yml`, `scripts/ci.sh`, and `scripts/ci-detect-changes.sh`; Depot workflows are legacy and should not be reintroduced.
- The frontend was merged into this repository by git subtree from the archived `Stygian-Tech/my-context-protocol-frontend` history.
- `mcp-server-kit` is the canonical external Swift package for reusable MCP protocol primitives. Local two-repo development may use a sibling checkout; GitHub Actions and Fly remote builds require a published Git revision.
- The internal MCP agent guide is maintained outside this open-source repo. Do not add Notion URLs or re-add an MCP agent guide file without an explicit request.
