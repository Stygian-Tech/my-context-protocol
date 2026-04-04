## Learned User Preferences

- Prefer GitHub OAuth for end-user auth and keep stored account data minimal (aligned with the frontend API contract).
- When a plan is explicitly MVP-scoped, implement MVP only and avoid scope creep into listed non-goals (e.g. teams, custom domains, marketplace).
- Do not duplicate or back-document work in Notion when the spec already lives there; implement in the codebase.
- **Exception:** The **MCP agent guide** (what agents and MCP clients see at the hosted endpoint) is maintained in the team’s **internal Notion** workspace (page title: **MCP agent guide (MyContextProtocol)**). **Do not add Notion URLs to this repository**—the app is open source while product docs stay private. It is not stored under `Docs/` in this repo; update the internal page when behavior changes. Do not re-add `Docs/MCP_AGENT_GUIDE.md` without an explicit request.
- Treat skill repositories as often using a flat `skill_name/SKILL.md` layout, not only `.agents/skills/`-style trees.
- When executing an attached implementation plan, do not edit the plan file; use existing todos as given.

## Learned Workspace Facts

- The product is split across two repos: Swift/Vapor backend in this directory and a Next.js frontend in `my-context-protocol-frontend`.
- The backend targets Swift 6 strict concurrency and uses VaporTesting-style async tests (not legacy XCTVapor-only patterns).
- Auth uses GitHub OAuth and session cookies; CORS is configured with `CORS_ORIGIN` for the frontend origin.
- Hosted SaaS behavior is documented in `Docs/SAAS_ARCHITECTURE.md`: per-`RepoConnection` encrypted GitHub tokens, per-connection webhook secrets, `WEBHOOK_BASE_URL`, and `ENCRYPTION_KEY` (global `GITHUB_TOKEN` / `WEBHOOK_SECRET` are legacy fallbacks).
- Backend API and contracts are described under `Docs/` when present (e.g. `BACKEND_API_CONTRACT.md`). **MCP client/agent semantics** for contributors (initialize payload, `mycontext:catalog`, SSE, catalog revision) are covered in tests and implementation; the prose agent guide is **team-internal Notion only** (same page title as above)—never link it from this repo.
- Local secrets files: `.env` and `.env.test` belong in `.gitignore`; if `DATABASE_URL` is set in `.env.test`, tests can run against dev Postgres (e.g. Supabase), otherwise they fall back to SQLite in-memory.
- Platform intent: compile human-authored `SKILL.md` packages from Git into typed, policy-aware MCP capabilities served from stable hosted endpoints—not only mirroring raw repo files.
