# SaaS Architecture: Private Repos & Webhooks

This document outlines the changes needed to support a multi-tenant SaaS where users connect their own private repos. Tokens and webhook secrets move from environment variables into the application/database.

---

## Current State (Self-Hosted)


| Concern                  | Current                       | Problem for SaaS                                     |
| ------------------------ | ----------------------------- | ---------------------------------------------------- |
| **Repo fetch**           | `GITHUB_TOKEN` env var        | Single token can't access every user's private repos |
| **Webhook verification** | `WEBHOOK_SECRET` env var      | Single secret; each webhook needs its own            |
| **Connect repo**         | Stores owner/repo/branch only | No token stored; no webhook created                  |
| **Webhook creation**     | None                          | User must manually add webhook in GitHub             |


---

## Target Architecture

### 1. Per-Connection Token Storage

Each `RepoConnection` needs a GitHub token that can access that specific repo (including private).

**Options:**

- **A) OAuth token (user's GitHub)**  
  - Add `repo` scope when user connects a repo.  
  - Store access token (encrypted) per connection or per account.  
  - Use for repo fetch + webhook creation.
- **B) GitHub App**  
  - Users install app on their repo/org.  
  - Use installation tokens for repo access.  
  - Webhooks created automatically.  
  - More setup, better for production SaaS.

**Recommendation:** Start with A (OAuth) to reuse existing flow; consider B later.

**Schema:** Add encrypted token storage. `token_ref` exists but is unused. Options:

- New column `token_encrypted` (encrypt with app-level `ENCRYPTION_KEY`)
- Or `token_ref` pointing at a secrets table / external secrets manager

---

### 2. Per-Connection Webhook Secret

Each webhook has its own secret. When creating a webhook, we generate a secret and store it on `RepoConnection`.

**Schema change:**

- Add `webhook_secret` to `RepoConnection` (nullable; set when webhook is created)

**Webhook verification flow:**

1. Parse payload to get `repository.full_name` (owner/repo).
2. Load `RepoConnection` by owner/repo.
3. Use `connection.webhook_secret` for HMAC verification.
4. If no connection or no secret, return 401 (or 404 to avoid leaking info).

---

### 3. Connect-Repo Flow (Updated)

When a user connects a repo:

1. **Obtain token**
  - If OAuth: ensure `repo` scope; store token from session or re-auth.
  - If PAT: accept token in request body (one-time), store encrypted.
  - Validate token by calling `GET /repos/:owner/:repo` and checking access.
2. **Create webhook**
  - Generate `webhook_secret` (e.g. 32 random bytes, hex).
  - Call `POST /repos/:owner/:repo/hooks` with:
    - `config.url`: `{APP_URL}/webhooks/github` (from env, e.g. `WEBHOOK_BASE_URL`)
    - `config.secret`: `webhook_secret`
    - `events`: `["push"]`
  - Store `webhook_id` and `webhook_secret` on `RepoConnection`.
3. **Store token**
  - Encrypt and save token (per connection or per account, depending on design).
4. **Save connection**
  - Persist owner, repo, branch, auth_type, webhook_id, webhook_secret, token_ref.

---

### 4. Repo Fetch (Updated)

`RepoFetcher` must use the connection’s token instead of `GITHUB_TOKEN`.

**Changes:**

- `RepoFetcher.fetch(owner:repo:ref:token:)` — add `token` parameter.
- `SyncPipeline` loads connection, decrypts token, passes to fetcher.
- If no token, fail with a clear error (e.g. "Repo not connected" or "Reconnect repo").

---

### 5. Webhook Handler (Updated)

**Changes:**

- Remove `WEBHOOK_SECRET` env usage.
- Look up `RepoConnection` by `owner/repo` from payload.
- Use `connection.webhook_secret` for HMAC verification.
- If connection not found or secret missing, return 401.

---

### 6. Configuration (Env)


| Env Var                                    | Purpose                                               |
| ------------------------------------------ | ----------------------------------------------------- |
| `WEBHOOK_BASE_URL`                         | Base URL for webhooks, e.g. `https://api.example.com` |
| `ENCRYPTION_KEY`                           | Key for encrypting stored tokens (32 bytes, base64)   |
| `GITHUB_CLIENT_ID`, `GITHUB_CLIENT_SECRET` | OAuth (unchanged)                                     |


Remove: `GITHUB_TOKEN`, `WEBHOOK_SECRET` (or keep only as fallback for migration).

---

## OAuth Scope Strategy

- **Initial login:** `read:user`, `user:email` (current).
- **Connect repo:** Need `repo` (full repo access) or `public_repo` (public only).
- **Flow:** When user hits connect-repo, if we don’t have a token with `repo`:
  - Redirect to GitHub OAuth with `repo` and `state` pointing back to connect-repo.
  - On callback, store token and complete connect-repo.

Alternative: Request `repo` on first login so we always have it.

---

## API Contract Updates

Connect-repo may need to support:

1. **OAuth path (default):** No extra body; use stored OAuth token. If missing `repo` scope, return error asking user to re-authorize.
2. **PAT path (optional):** Body `{ "owner", "repo", "branch", "token" }` for users who prefer a PAT.

---

## Implementation Order

1. Schema: add `webhook_secret` to `RepoConnection`; add token storage (column or table).
2. Token encryption helper (encrypt/decrypt with `ENCRYPTION_KEY`).
3. WebhookController: verify using per-connection secret.
4. RepoFetcher: accept token parameter; Pipeline passes connection token.
5. Connect-repo: OAuth scope + token storage, webhook creation, secret storage.
6. Env: add `WEBHOOK_BASE_URL`, `ENCRYPTION_KEY`; deprecate `GITHUB_TOKEN`, `WEBHOOK_SECRET`.

---

## Security Notes

- Encrypt tokens at rest.
- Prefer short-lived tokens where possible (GitHub OAuth tokens are long-lived).
- Rotate `ENCRYPTION_KEY` with a migration path for re-encrypting tokens.
- Never log or expose tokens or webhook secrets.

