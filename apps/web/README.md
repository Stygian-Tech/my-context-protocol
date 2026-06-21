# MyContextProtocol Frontend

Dashboard for **MyContextProtocol**—a hosted MCP endpoint that syncs SKILL.md files from Git repositories.

## Tech Stack

- **Runtime:** Bun
- **Framework:** Next.js 16 (App Router)
- **Language:** TypeScript
- **Styling:** Tailwind CSS
- **Components:** Shadcn UI
- **Data fetching:** TanStack Query
- **Forms:** React Hook Form + Zod

## Prerequisites

- [Bun](https://bun.sh) (v1.3.7; see repo-root `.bun-version`). Install from the repository root so Bun workspaces use the root `bun.lock`.

## Getting Started

1. Install dependencies:

   ```bash
   cd ../..
   bun install
   cd apps/web
   ```

2. Copy the example environment file:

   ```bash
   cp .env.example .env
   ```

3. Set `NEXT_PUBLIC_API_URL` in `.env` to your backend API base URL (e.g. `http://localhost:8080`).

4. Start the development server:

   ```bash
   bun run dev
   ```

5. Open [http://localhost:3000](http://localhost:3000).

## Environment Variables

| Variable                      | Description                                                |
| ----------------------------- | ---------------------------------------------------------- |
| `NEXT_PUBLIC_API_URL`         | Backend API base URL (Vapor server)                        |
| `NEXT_PUBLIC_APP_URL`         | Frontend URL for OAuth return (optional, defaults to origin) |
| `NEXT_PUBLIC_CLIENT_API_LOG`  | `0`/`false` disables `[client-api]` console traces; `1` forces them on (e.g. in tests). Default: on for local dev, Vercel preview, and when `NEXT_PUBLIC_APP_ENV` is `local` or `dev`; off in production and in Vitest. When on: logs request/response timing, warns on non-OK status, and prints a truncated error response body. |

When the backend sets `MCP_OAUTH_ENABLED`, project and catalog API responses include `mcp_oauth_enabled: true` and the dashboard **Connect** section documents OAuth discovery URLs on the MCP host (API keys stay supported).

## Project Structure

```
├── app/
│   ├── (dashboard)/       # Protected dashboard routes
│   │   ├── page.tsx       # Overview
│   │   ├── projects/     # Projects list & detail
│   │   └── layout.tsx     # Sidebar + header layout
│   ├── login/            # Login page
│   ├── layout.tsx         # Root layout
│   ├── error.tsx         # Error boundary
│   └── global-error.tsx  # Global error boundary
├── components/
│   ├── ui/               # Shadcn components
│   ├── layout/            # App sidebar, header
│   └── dashboard/        # Project card, releases, API keys, logs
├── contexts/              # Auth context
├── lib/
│   ├── api.ts            # API client
│   ├── auth.ts           # Auth helpers
│   ├── types.ts          # Re-exported shared types from @mycontext/web-client
│   └── projects-api.ts   # Project API calls
└── hooks/
```

## Backend Integration

This frontend is designed to work with the MyContextProtocol Vapor backend. Authentication uses **GitHub OAuth** (no local email/password). The backend must expose:

**Auth (GitHub OAuth):**
- `GET /auth/github?return_to=<url>` — Redirects to GitHub OAuth; after success, redirects to `return_to` with session cookie
- `GET /auth/github/callback` — GitHub OAuth callback (receives `code`, exchanges for token, creates session)
- `POST /auth/logout` — Invalidate session
- `GET /auth/me` — Current user (for session check)

**Other REST endpoints:**
- `GET /projects` — List projects
- `GET /projects/:id` — Project detail
- `POST /projects` — Create project
- `GET /projects/:id/repo-connection` — Repo connection status
- `POST /projects/:id/connect-repo` — Connect GitHub repo
- `POST /projects/:id/sync` — Trigger sync
- `GET /projects/:id/releases` — Release history
- `POST /projects/:id/releases/:releaseId/activate` — Activate release
- `GET /projects/:id/api-keys` — List API keys
- `POST /projects/:id/api-keys` — Create API key
- `GET /projects/:id/request-logs` — Request logs
- `GET /projects/:id/catalog` — Active-release MCP catalog (tools, resources, prompts) for the dashboard

Configure CORS on the backend to allow the frontend origin.

For the backend API contract, see [`../../packages/mycontext-api-contract/BACKEND_API_CONTRACT.md`](../../packages/mycontext-api-contract/BACKEND_API_CONTRACT.md).

## Scripts

| Command        | Description              |
| -------------- | ------------------------ |
| `bun run dev`  | Start dev server          |
| `bun run build`| Production build         |
| `bun run start`| Start production server  |
| `bun run lint` | Run ESLint               |
| `bun run typecheck` | TypeScript check   |

## License

This workspace is part of MyContextProtocol and is released under the repository [MIT License](../../LICENSE).
