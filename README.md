# MyContextProtocol Frontend

Dashboard for [MyContextProtocol](https://www.notion.so/MyContextProtocol-325f6c1638ed80568b93dc8e6abba384)—a hosted MCP endpoint that syncs SKILL.md files from Git repositories.

## Tech Stack

- **Runtime:** Bun
- **Framework:** Next.js 15 (App Router)
- **Language:** TypeScript
- **Styling:** Tailwind CSS
- **Components:** Shadcn UI
- **Data fetching:** TanStack Query
- **Forms:** React Hook Form + Zod

## Prerequisites

- [Bun](https://bun.sh) (v1.0+)
- Node.js 20+ (if not using Bun)

## Getting Started

1. Install dependencies:

   ```bash
   bun install
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

| Variable               | Description                          |
| ---------------------- | ------------------------------------ |
| `NEXT_PUBLIC_API_URL`  | Backend API base URL (Vapor server) |

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
│   ├── types.ts          # Shared types
│   └── projects-api.ts   # Project API calls
└── hooks/
```

## Backend Integration

This frontend is designed to work with the MyContextProtocol Vapor backend. The backend must expose these REST endpoints:

- `POST /auth/login` — Email + password → session/JWT
- `POST /auth/logout` — Invalidate session
- `GET /auth/me` — Current user (optional, for session check)
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

Configure CORS on the backend to allow the frontend origin.

## Scripts

| Command        | Description              |
| -------------- | ------------------------ |
| `bun run dev`  | Start dev server          |
| `bun run build`| Production build         |
| `bun run start`| Start production server  |
| `bun run lint` | Run ESLint               |
| `bun run typecheck` | TypeScript check   |
