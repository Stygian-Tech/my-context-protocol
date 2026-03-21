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

- `return_to`: Full URL to redirect the user after successful login (e.g. `http://localhost:3000/` or `http://localhost:3000/projects`).
- No auth required.
- Backend should redirect to GitHub OAuth.

**Response:** 302 redirect to GitHub.

---

### 2. OAuth callback

**Request**

```
GET /auth/github/callback?code=<code>&state=<state>
```

- GitHub sends the user here after authorization.
- Backend exchanges `code` for tokens, creates/updates user, creates session.
- Backend redirects to the `return_to` URL with `?auth_token=<one-time-token>`.
- Frontend must call `GET /auth/confirm?token=<auth_token>` with `credentials: "include"` to exchange the token for a session. The response `Set-Cookie` establishes the session in the same context as API calls (avoids redirect/cookie issues in embedded browsers).

**Response:** 200 OK with HTML page that meta-refreshes to `return_to?auth_token=<token>`.

---

### 3. Confirm auth (token exchange)

**Request**

```
GET /auth/confirm?token=<auth_token>
```

- Called by the frontend when it has `auth_token` in the URL (from OAuth redirect).
- Must use `credentials: "include"`.
- Exchanges the one-time token for a session. Response `Set-Cookie` establishes the session.
- Token is single-use and expires in 5 minutes.

**Response:** `200 OK` with `UserResponse` JSON and `Set-Cookie` for session.

- `400` if token missing.
- `401` if token invalid or expired.

---

### 4. Current user (session check)

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
  "avatar_url": "string | undefined",
  "plan": "free | pro",
  "internal_pro_bypass": "boolean",
  "can_manage_subscription": "boolean",
  "suggested_github_app_install": "boolean"
}
```

- `suggested_github_app_install`: `true` when the user is **Pro**, `GITHUB_APP_SLUG` and `WEBHOOK_BASE_URL` are configured, and at least one GitHub `repo_connection` has no `github_installation_id` (frontend may show “Install GitHub App” → `GET /auth/github/app/install`).
- `plan` is `pro` when Stripe subscription is active/trialing **or** the account matches `INTERNAL_PRO_GITHUB_LOGINS` / `INTERNAL_PRO_GITHUB_IDS`.
- `internal_pro_bypass`: `true` if the account is on those env allowlists (whether or not they also pay via Stripe).
- `can_manage_subscription`: `true` if a Stripe Customer exists (`stripe_customer_id`), so Customer Portal can be used.
- `401 Unauthorized` if not authenticated (frontend treats this as “logged out”).

---

### 5. Logout

**Request**

```
POST /auth/logout
```

- Requires valid session cookie.
- Invalidates the session.

**Response:** `200 OK` or `204 No Content`. Body is ignored.

---

### 5b. Install GitHub App (Pro — session)

**Request**

```
GET /auth/github/app/install?project_id=<uuid>&return_to=<url optional>
```

- Requires session.
- Redirects to `https://github.com/apps/{GITHUB_APP_SLUG}/installations/new?state=...`.
- **Setup URL** in the GitHub App settings must point to `GET /auth/github/app/callback` on this API.

**Callback (browser, session cookie)**

```
GET /auth/github/app/callback?installation_id=<id>&setup_action=install&state=<state>
```

- Persists `installation_id` on the project’s existing `repo_connection`, or stores it in session until `POST /projects/:id/connect-repo` runs.

---

### 6. List GitHub repositories (session)

**Request**

```
GET /github/repos
```

- Requires valid session cookie.
- Uses the stored GitHub OAuth token to call GitHub `GET /user/repos` (paginated server-side, sorted by `updated`, affiliations: owner, collaborator, organization member).

**Response:** `200 OK` with JSON array of:

```json
{
  "full_name": "owner/repo",
  "owner_login": "owner",
  "name": "repo",
  "default_branch": "main",
  "is_private": false
}
```

- `400` if no GitHub token on the account (user should sign in again).
- `502` if GitHub API fails or returns unexpected data.

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
  "slug": "string"
}
```

- `slug` must be unique **per account** (`UNIQUE(account_id, slug)`).
- `subdomain` is **server-assigned** (random); clients must not send it.

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

- **Pro** (active/trialing subscription): creates a GitHub repo webhook when `WEBHOOK_BASE_URL` is set; `webhook_id` is populated. If `github_installation_id` is set (install flow or reconnect), hook CRUD uses a **GitHub App installation access token**; otherwise the user **OAuth** token is used.
- **Free:** connection is stored but **no** webhook; `webhook_id` is null — user relies on **manual sync**.

---

### Trigger sync

**Request**

```
POST /projects/:id/sync
```

**Response:** `200 OK` or `204 No Content`. Body is ignored.

- Rate-limited per account+project for **both** Free and Pro (manual sync remains on Pro). **`429 Too Many Requests`** with `Retry-After` when exceeded.

---

### Custom domain (Pro)

**GET** `/projects/:id/custom-domain` — `CustomDomainResponse`.

**POST** `/projects/:id/custom-domain` — body `{ "hostname": "string" }`. Sets pending domain and verification token; **`402`** if not Pro.

**POST** `/projects/:id/custom-domain/verify` — checks DNS (TXT) via DoH; **`402`** if not Pro.

---

### Billing (Stripe)

**POST** `/billing/checkout-session` — body optional `{ "interval": "month" | "year", "success_path", "cancel_path" }`. `interval` defaults to `"month"` and selects `STRIPE_PRICE_PRO_MONTHLY` vs `STRIPE_PRICE_PRO_YEARLY` (or legacy `STRIPE_PRICE_PRO` for monthly). Returns `{ "url": "https://checkout.stripe.com/..." }`. **`503`** if the Price ID for the chosen interval is not configured.

**POST** `/billing/portal-session` — returns Stripe Customer Portal URL. **`400`** if no `stripe_customer_id`.

**POST** `/webhooks/stripe` — Stripe signed webhooks (raw body). Not called by the SPA.

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

**Errors:** `400` if release status is not `ready` or if any compiled skill has status other than `ready`.

---

### List compiled skills

**Request**

```
GET /projects/:id/releases/:releaseId/compiled-skills
```

**Response:** `CompiledSkill[]` — compiled skills for the release (for skill review UI).

---

### Update compiled skill

**Request**

```
PATCH /projects/:id/releases/:releaseId/compiled-skills/:compiledSkillId
Content-Type: application/json

{
  "exposure_type": "tool | resource | prompt",
  "risk_level": "low | medium | high",
  "status": "ready | needs_review | not_publishable"
}
```

**Response:** `CompiledSkill` object. All fields optional.

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
  "avatar_url": "string | undefined",
  "plan": "free | pro",
  "internal_pro_bypass": "boolean",
  "can_manage_subscription": "boolean"
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
  "created_at": "string",
  "custom_domain": "string | null | undefined",
  "custom_domain_verified_at": "string | null | undefined",
  "mcp_url": "string | null | undefined"
}
```

- `mcp_url`: Full URL for the MCP HTTP endpoint (`POST` + `SAAS_MCP_PATH`, default `/mcp`). Built on the server from `SAAS_MCP_URL_SCHEME` (default `https`), tenant host (`{subdomain}.{SAAS_MCP_BASE_DOMAIN}`) or **verified** `custom_domain`, and `SAAS_MCP_PATH`. `null` if `SAAS_MCP_BASE_DOMAIN` is unset and the project has no verified custom domain.

### CustomDomainResponse

```json
{
  "hostname": "string | null | undefined",
  "verified": "boolean",
  "verification_token": "string | null | undefined",
  "instructions": "string | null | undefined"
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
  "webhook_id": "string | null | undefined",
  "github_installation_configured": "boolean"
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

### CompiledSkill

```json
{
  "id": "string",
  "release_id": "string",
  "skill_package_id": "string",
  "path": "string",
  "name": "string",
  "summary": "string | null | undefined",
  "exposure_type": "string",
  "risk_level": "string",
  "repo_specific": "boolean",
  "status": "string"
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
| GET | `/auth/github/app/install` | Yes | Redirect to GitHub App installation |
| GET | `/auth/github/app/callback` | No (session) | GitHub App setup callback |
| GET | `/auth/me` | Yes | Current user |
| POST | `/auth/logout` | Yes | Logout |
| GET | `/github/repos` | Yes | List GitHub repos for OAuth token |
| GET | `/projects` | Yes | List projects |
| GET | `/projects/:id` | Yes | Get project |
| POST | `/projects` | Yes | Create project |
| GET | `/projects/:id/repo-connection` | Yes | Get repo connection |
| POST | `/projects/:id/connect-repo` | Yes | Connect repo |
| POST | `/projects/:id/sync` | Yes | Trigger sync (rate-limited) |
| GET | `/projects/:id/custom-domain` | Yes | Custom domain status (Pro) |
| POST | `/projects/:id/custom-domain` | Yes | Set custom domain hostname (Pro) |
| POST | `/projects/:id/custom-domain/verify` | Yes | Verify DNS TXT (Pro) |
| POST | `/billing/checkout-session` | Yes | Stripe Checkout URL |
| POST | `/billing/portal-session` | Yes | Stripe Customer Portal URL |
| POST | `/webhooks/github` | No (HMAC per repo hook) | GitHub `push` → sync |
| POST | `/webhooks/github-app` | No (`GITHUB_APP_WEBHOOK_SECRET`) | App install/revoke lifecycle (optional) |
| POST | `/webhooks/stripe` | No (Stripe signature) | Subscription webhooks |
| GET | `/projects/:id/releases` | Yes | List releases |
| POST | `/projects/:id/releases/:releaseId/activate` | Yes | Activate release |
| GET | `/projects/:id/releases/:releaseId/compiled-skills` | Yes | List compiled skills |
| PATCH | `/projects/:id/releases/:releaseId/compiled-skills/:compiledSkillId` | Yes | Update compiled skill |
| GET | `/projects/:id/api-keys` | Yes | List API keys |
| POST | `/projects/:id/api-keys` | Yes | Create API key |
| GET | `/projects/:id/request-logs` | Yes | List request logs |
