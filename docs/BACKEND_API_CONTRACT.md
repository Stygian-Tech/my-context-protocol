# Backend API Contract

This document describes what the MyContextProtocol frontend expects from the backend API. Use it when implementing or integrating the backend.

---

## Overview

- **Auth:** GitHub OAuth (no email/password). Session-based via cookies.
- **Transport:** REST over HTTP/HTTPS. All requests use `Content-Type: application/json` and `credentials: "include"` (cookies).
- **Base URL:** Configurable via `NEXT_PUBLIC_API_URL` (e.g. `http://localhost:8080`).

---

## CORS & Credentials

The frontend runs on a different origin (e.g. `http://localhost:3000`). The backend must:

1. **Allow the frontend origin** in CORS (e.g. `http://localhost:3000` in dev, production URL in prod).
2. **Allow credentials** (`Access-Control-Allow-Credentials: true`).
3. **Set cookies** with `SameSite` and `Secure` appropriate for your setup (e.g. `SameSite=Lax` for same-site in dev).

---

## Authentication (GitHub OAuth)

### 1. Initiate login

**Request**

```
GET /auth/github?return_to=<url>
```

- `return_to`: Full URL to redirect the user after successful login (e.g. `http://localhost:3000/` or `http://localhost:3000/projects`). If omitted, the backend uses `FRONTEND_URL` or `CORS_ORIGIN` + `/` when configured.
- When `FRONTEND_URL` / `CORS_ORIGIN` are set, `return_to` must match one of those origins (open-redirect protection).
- No auth required.
- Backend redirects to GitHub OAuth with a **signed** `state` parameter (HMAC via `ENCRYPTION_KEY`) so the post-login redirect does not rely on in-memory sessions or sticky load balancers.
- Requires `GITHUB_OAUTH_REDIRECT_URI` and `ENCRYPTION_KEY` (32-byte base64) to be configured.

**Response:** 302 redirect to GitHub.

---

### 2. OAuth callback

**Request**

```
GET /auth/github/callback?code=<code>&state=<state>
```

- GitHub sends the user here after authorization.
- Backend exchanges `code` for tokens, creates/updates user, creates session.
- Backend redirects to the `return_to` URL encoded in signed `state` with `?auth_token=<one-time-token>`. If `state` is missing or invalid, the user is sent to `/login?error=...` when `FRONTEND_URL` / `CORS_ORIGIN` is set, otherwise `400`.

**Response:** 302 redirect to `return_to` with `auth_token`; session is finalized via `/auth/confirm`.

---

### 3. Current user (session check)

**Request**

```
GET /auth/me
```

- Requires valid session cookie.
- Used to check if user is logged in.

**Response:** `200 OK` with JSON body:

```json
{
  "id": "string",
  "email": "string | undefined",
  "login": "string | undefined",
  "avatar_url": "string | undefined"
}
```

- `401 Unauthorized` if not authenticated (frontend treats this as “logged out”).

---

### 4. Logout

**Request**

```
POST /auth/logout
```

- Requires valid session cookie.
- Invalidates the session.

**Response:** `200 OK` or `204 No Content`. Body is ignored.

---

## Projects API

### List projects

**Request**

```
GET /projects
```

**Response:** Either:

- `Project[]` (array of projects), or
- `{ "projects": Project[] }`

---

### Get project

**Request**

```
GET /projects/:id
```

**Response:** `Project` object.

**Errors:** `404` if project not found.

---

### Create project

**Request**

```
POST /projects
Content-Type: application/json

{
  "name": "string",
  "slug": "string",
  "subdomain": "string"
}
```

**Response:** `Project` object (the created project).

---

### Get repo connection

**Request**

```
GET /projects/:id/repo-connection
```

**Response:** `RepoConnection` object if connected, or `404` if not connected.  
The frontend treats any error (including 404) as “no connection” and returns `null`.

---

### Connect repo

**Request**

```
POST /projects/:id/connect-repo
Content-Type: application/json

{
  "owner": "string",
  "repo": "string",
  "branch": "string"
}
```

**Response:** `RepoConnection` object.

---

### Trigger sync

**Request**

```
POST /projects/:id/sync
```

**Response:** `200 OK` or `204 No Content`. Body is ignored.

---

### List releases

**Request**

```
GET /projects/:id/releases
```

**Response:** Either:

- `Release[]`, or
- `{ "releases": Release[] }`

---

### Activate release

**Request**

```
POST /projects/:id/releases/:releaseId/activate
```

**Response:** `200 OK` or `204 No Content`. Body is ignored.

---

### List API keys

**Request**

```
GET /projects/:id/api-keys
```

**Response:** Either:

- `ApiKey[]`, or
- `{ "api_keys": ApiKey[] }`

---

### Create API key

**Request**

```
POST /projects/:id/api-keys
```

No request body.

**Response:** JSON body:

```json
{
  "key": "string",
  "prefix": "string"
}
```

- `key`: Full API key (shown once to the user).
- `prefix`: Key prefix for display (e.g. `mcp_abc123...`).

---

### List request logs

**Request**

```
GET /projects/:id/request-logs?limit=<n>&offset=<n>
```

- `limit` (optional): Max number of logs.
- `offset` (optional): Pagination offset.

**Response:** Either:

- `RequestLog[]`, or
- `{ "logs": RequestLog[] }`

---

## Type Definitions

Use these shapes for request/response bodies.

### User

```json
{
  "id": "string",
  "email": "string | undefined",
  "login": "string | undefined",
  "avatar_url": "string | undefined"
}
```

### Project

```json
{
  "id": "string",
  "account_id": "string",
  "name": "string",
  "slug": "string",
  "subdomain": "string",
  "created_at": "string"
}
```

### RepoConnection

```json
{
  "project_id": "string",
  "provider": "string",
  "repo_owner": "string",
  "repo_name": "string",
  "default_branch": "string",
  "auth_type": "string",
  "webhook_id": "string | null | undefined"
}
```

### Release

```json
{
  "id": "string",
  "project_id": "string",
  "commit_sha": "string",
  "status": "pending | ready | failed",
  "created_at": "string",
  "error_summary": "string | null | undefined"
}
```

### ApiKey

```json
{
  "id": "string",
  "project_id": "string",
  "key_prefix": "string",
  "status": "string",
  "created_at": "string",
  "last_used_at": "string | null | undefined"
}
```

### RequestLog

```json
{
  "id": "string",
  "project_id": "string",
  "release_id": "string | null | undefined",
  "timestamp": "string",
  "client_id": "string | null | undefined",
  "method": "string",
  "latency_ms": "number | null | undefined",
  "status": "number",
  "error_code": "string | null | undefined"
}
```

---

## Error Handling

- The frontend expects JSON error bodies when `Content-Type` is `application/json`.
- On non-2xx responses, the frontend throws an `ApiError` with `status` and optional `body`.
- `401` on `/auth/me` is treated as “not logged in” (no user).
- `404` on `/projects/:id/repo-connection` is treated as “no repo connected”.

---

## Endpoint Summary

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| GET | `/auth/github` | No | Start GitHub OAuth |
| GET | `/auth/github/callback` | No | OAuth callback |
| GET | `/auth/me` | Yes | Current user |
| POST | `/auth/logout` | Yes | Logout |
| GET | `/projects` | Yes | List projects |
| GET | `/projects/:id` | Yes | Get project |
| POST | `/projects` | Yes | Create project |
| GET | `/projects/:id/repo-connection` | Yes | Get repo connection |
| POST | `/projects/:id/connect-repo` | Yes | Connect repo |
| POST | `/projects/:id/sync` | Yes | Trigger sync |
| GET | `/projects/:id/releases` | Yes | List releases |
| POST | `/projects/:id/releases/:releaseId/activate` | Yes | Activate release |
| GET | `/projects/:id/api-keys` | Yes | List API keys |
| POST | `/projects/:id/api-keys` | Yes | Create API key |
| GET | `/projects/:id/request-logs` | Yes | List request logs |
