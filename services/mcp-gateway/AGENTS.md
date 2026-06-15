## Learned User Preferences

- Prefer GitHub OAuth for end-user auth and keep stored account data minimal (aligned with the frontend API contract).
- When a plan is explicitly MVP-scoped, implement MVP only and avoid scope creep into listed non-goals (e.g. teams, custom domains, marketplace).
- Do not duplicate or back-document work in Notion when the spec already lives there; implement in the codebase.
- **Exception:** The **MCP agent guide** (what agents and MCP clients see at the hosted endpoint) is maintained in the team’s **internal Notion** workspace (page title: **MCP agent guide (MyContextProtocol)**). **Do not add Notion URLs to this repository**—the app is open source while product docs stay private. It is not stored under `Docs/` in this repo; update the internal page when behavior changes. Do not re-add `Docs/MCP_AGENT_GUIDE.md` without an explicit request.
- Treat skill repositories as often using a flat `skill_name/SKILL.md` layout, not only `.agents/skills/`-style trees.
- When executing an attached implementation plan, do not edit the plan file; use existing todos as given.
- Prefer MCP tool and prompt names exposed on the wire without colons when evolving naming or integrations; some MCP clients and editors mishandle colon-containing identifiers.
- For English UI that combines a count with a verb phrase, pluralize whole tails (for example singular vs plural “skill needs …” / “skills need …”) so grammar stays correct; keep the same phrasing for visible labels and aria-labels.
- For the Next.js dashboard, use title case on short chrome (buttons, dialog titles, navigation, tooltips, compact headings); keep sentence case for long explanatory copy, validation lines, and dynamically composed sentences; avoid heavy title casing on very long aria-labels when it hurts screen reader clarity.

## Learned Workspace Facts

- The product is now a monorepo: Swift/Vapor backend in `services/mcp-gateway`, Next.js frontend in `apps/web`, and shared contract/type packages in `packages/*`.
- The backend targets Swift 6 strict concurrency and uses VaporTesting-style async tests (not legacy XCTVapor-only patterns).
- Auth uses GitHub OAuth and session cookies; CORS is configured with `CORS_ORIGIN` for the frontend origin.
- MCP OAuth handoff after GitHub login resumes on the frontend at `/auth/mcp-oauth-resume` (with `pending` in the query), not `/auth/mcp-oauth/resume`. For verified custom MCP domains behind a TLS-terminating reverse proxy, enable `MCP_TRUST_X_FORWARDED_HOST` only when the edge sets or overwrites `X-Forwarded-Host` to the public hostname so tenant resolution matches the custom domain.
- Hosted SaaS behavior is documented in `Docs/SAAS_ARCHITECTURE.md`: per-`RepoConnection` encrypted GitHub tokens, per-connection webhook secrets, `WEBHOOK_BASE_URL`, and `ENCRYPTION_KEY` (global `GITHUB_TOKEN` / `WEBHOOK_SECRET` are legacy fallbacks).
- Backend API and contracts are described under `packages/mycontext-api-contract` when present. **MCP client/agent semantics** for contributors (initialize payload, `mycontext_catalog`, SSE, catalog revision) are covered in tests and implementation; the prose agent guide is **team-internal Notion only** (same page title as above)—never link it from this repo.
- Local secrets files: `.env` and `.env.test` belong in `.gitignore`; if `DATABASE_URL` is set in `.env.test`, tests can run against dev Postgres (e.g. Supabase), otherwise they fall back to SQLite in-memory. Vapor loads `.env` for normal local app runs (e.g. `swift run App`), not `.env.test`; use `.env` or exported env vars when running the server against a real database.
- Optional local demo fixtures: `LocalDevFixtures.seedIfNeeded` runs on app boot when `SEED_LOCAL_FIXTURES=1` and the environment is allowed for seeding (`APP_ENV=local`, or non-production with file SQLite via `USE_SQLITE=1`); fixtures attach to the oldest account—sign in with GitHub once, then restart with the flag. See `Sources/App/Services/LocalDevFixtures.swift`.
- Platform intent: compile human-authored `SKILL.md` packages from Git into typed, policy-aware MCP capabilities served from stable hosted endpoints—not only mirroring raw repo files.
