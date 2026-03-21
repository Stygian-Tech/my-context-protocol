# Handoff: GitHub App for Pro repository webhooks

**Audience:** An implementer (human or agent) building a **GitHub App** so **Pro** users get automatic sync on `push` without relying on the user’s OAuth token to create **per-repository** webhooks.

**Product context:** [MyContextProtocol](.) is a hosted MCP/skill sync service. Users connect a GitHub repo; **Pro** entitlements enable **automatic sync** when code is pushed. Today that uses a **GitHub OAuth App** (`repo` scope) and the REST **Repository Webhooks** API. This document describes that contract and how a **GitHub App** should satisfy it (or what must change on the server if you choose App-level webhooks instead).

**Related internal note:** See [`GITHUB_APP_PHASE2.md`](./GITHUB_APP_PHASE2.md) for broader goals (installation IDs, narrower OAuth).

---

## 1. Current behavior (reference implementation)

| Piece | Behavior |
|--------|----------|
| **Who gets a webhook** | Accounts with **Pro** entitlements (`hasProEntitlements`), when connecting a repo, **if** `WEBHOOK_BASE_URL` is set on the server. |
| **How the hook is created** | `POST https://api.github.com/repos/{owner}/{repo}/hooks` with a **Bearer** token (today: decrypted user OAuth token). |
| **Delivery URL** | `{WEBHOOK_BASE_URL}` + `/webhooks/github` (slash normalized). Example: `https://api.example.com/webhooks/github`. |
| **Hook configuration** | `name: "web"`, `config.content_type: "json"`, `config.secret: <random 32-byte hex string>`, `events: ["push"]`. |
| **Stored server-side** | `webhook_id` (GitHub hook id as string), `webhook_secret` (same hex secret) on `repo_connections`. |
| **Reconnect / change repo** | Old hook is **deleted** (`DELETE .../hooks/{hook_id}`) before creating a new one (same token source today). |
| **Pro downgrade** | `GitHubWebhookCleanup` deletes hooks using the **user OAuth token** and clears `webhook_id` / `webhook_secret`. |

Source files (for exact JSON and verification):

- `Sources/App/Services/GitHubWebhookService.swift` — create/delete hook, repo access check.
- `Sources/App/Controllers/ProjectController.swift` — `connectRepo` Pro branch.
- `Sources/App/Controllers/WebhookController.swift` — inbound delivery handler.
- `Sources/App/Services/GitHubWebhookCleanup.swift` — teardown on downgrade.

---

## 2. Inbound webhook contract (must not break)

The backend exposes:

```http
POST /webhooks/github
```

**No session cookie.** This endpoint is **public**; security is **HMAC-SHA256** of the **raw** JSON body.

### Headers

- **`X-Hub-Signature-256`**: required **if** the matching `RepoConnection` has a non-empty `webhook_secret`. Format: `sha256=<lowercase hex of HMAC-SHA256(body, secret)>` where `secret` is the **UTF-8 bytes** of the hex string stored at hook creation (not decoded from hex—use the string as the HMAC key exactly as GitHub received it in `config.secret`).

### Body (minimal fields used today)

The handler decodes JSON and uses:

- `repository.full_name` — must be `owner/repo` (used to find `RepoConnection` by `repo_owner` + `repo_name`).
- `ref` — present on push payloads (not strictly validated for routing today; sync runs for the whole project).

If no `RepoConnection` matches `repository.full_name`, the server still returns **200** with `{"ok":true}` (idempotent / ignore unknown repos).

### Response

- **200** with body `{"ok":true}` on success or when no matching connection.
- **400** if body missing/invalid or `repository.full_name` missing.
- **401** if signature required and missing or wrong.

**Important:** The GitHub App (or any hook you register) must send **`push`** events with a JSON body that includes `repository.full_name` in the standard GitHub push payload shape.

---

## 3. Goal of the GitHub App (this handoff)

**Primary goal:** For **Pro** users, register and maintain the **same style** of **repository webhook** (same URL path, same `content_type`, same `push`-only events, same secret model) using **GitHub App credentials**—typically an **installation access token**—so you do **not** depend on the user’s OAuth token for hook CRUD.

**Non-goals for the App itself:**

- Replacing user login (OAuth for identity can remain as today).
- Changing the inbound URL or signature algorithm without a coordinated backend change.

---

## 4. Registering the GitHub App (GitHub.com UI)

1. **GitHub → Settings → Developer settings → GitHub Apps → New GitHub App.**

2. **Webhook URL (optional for this design):**  
   - If you use **only per-repo hooks** created via API (mirror current backend), you may leave the **App-level** “Webhook URL” empty or point it to a no-op; delivery for sync uses **repository webhooks** you create.  
   - Alternatively, you can use **one App webhook** for all events and **drop per-repo hooks**—that requires **backend changes** (see §6).

3. **Webhook secret (App-level):** Only used if you use the App’s default webhook endpoint—not used by today’s `WebhookController` per-repo secret model.

4. **Repository permissions** (minimum to mirror `GitHubWebhookService`):

   - **Contents:** Read (for future fetch/sync via installation token; sync today uses stored OAuth token in other code paths—plan for App token separately).
   - **Metadata:** Read (always recommended).
   - **Webhooks** or equivalent to create/manage **repository hooks:** you need permission to call `POST/DELETE /repos/{owner}/{repo}/hooks`. In GitHub’s permission model this is often **“Administration”** and/or **“Webhooks”** at **repository** scope—verify against current GitHub App permission docs when you register.

5. **Subscribe to events (if using App-level webhook):** `Push`, and possibly `Installation` / `Installation repositories` to track which repos are valid. **Not required** if you only use programmatic repo webhooks identical to today.

6. **Where can this GitHub App be installed?** Choose **Any account** or **Only this organization** per product policy.

7. After creation, note **App ID**, generate and download **private key** (PEM), and record **Client ID** / **Client secret** if you add a User-to-server or OAuth flow for the App.

Official references:

- [Creating a GitHub App](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app)
- [Webhook events for GitHub Apps](https://docs.github.com/en/webhooks/webhook-events-and-payloads)
- [Permissions for GitHub Apps](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app#choosing-permissions-for-a-github-app)

---

## 5. Authenticating to create repository webhooks

To call `POST /repos/{owner}/{repo}/hooks` as an App:

1. **JWT** — Authenticate as the app: sign a short-lived JWT with the App’s private key (`iss` = App ID, `iat`, `exp`, GitHub’s documented claims).
2. **Installation access token** — `POST /app/installations/{installation_id}/access_tokens` with the JWT; GitHub returns a token useable as `Authorization: Bearer …` for repository API calls scoped to that installation.

The **installation id** is tied to **where the user installed the app** (user account or org). Your product must persist `installation_id` for the account or per `RepoConnection` and use the correct installation when creating hooks for `owner/repo`.

References:

- [Authenticating as a GitHub App](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/authenticating-as-a-github-app)
- [Authenticating as an installation](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/authenticating-as-a-github-app-installation)

---

## 6. Integration architecture choices

### Option A — **Drop-in replacement** (recommended for minimal backend churn)

- Keep **`WebhookController`** and **`WEBHOOK_BASE_URL`** exactly as today.
- Replace `GitHubWebhookService.createWebhook` / `deleteWebhook` **token source**: use **installation access token** instead of user OAuth token when `installation_id` is known.
- **Cleanup on downgrade:** `GitHubWebhookCleanup` must use an **installation token** (or JWT-based app client) too—not the user OAuth token—if hooks were created with the App.

**Backend work (not in this repo as of this doc):** schema for `github_installation_id`, “Install GitHub App” UX, exchange `installation_id` after `installation` callback, and thread installation token into hook create/delete.

### Option B — **App-level webhook only**

- Configure the GitHub App’s **single** Webhook URL to `https://<api>/webhooks/github`.
- GitHub sends a **different** payload shape and signing secret (**App webhook secret**), not per-repo `webhook_secret` in DB.
- **Requires backend changes:** verify signature with App secret, map `installation` + repository to project, possibly ignore per-row `webhook_secret` or store App secret globally.

Use Option B only if you explicitly want one endpoint and no per-repo hook records.

---

## 7. Pro gating (product rule)

Only **Pro** users should trigger hook registration. Today the server checks `account.hasProEntitlements` in `connectRepo`. The GitHub App layer should enforce the same rule (or stricter): no hook creation for Free tier.

---

## 8. Environment / ops checklist

| Variable | Role |
|----------|------|
| `WEBHOOK_BASE_URL` | Public base URL of the API **reachable by GitHub** (no trailing slash required; code normalizes). Used when **registering** the hook URL. |

Ensure TLS, no auth wall on `POST /webhooks/github`, and firewall allows GitHub’s IP ranges (or use documented webhook delivery behavior for your hosting).

---

## 9. Verification checklist (for the implementer)

- [ ] Pro account: connect repo → GitHub shows a **web** hook on that repo pointing at `{WEBHOOK_BASE_URL}/webhooks/github`, **push** events only, **JSON** payload.
- [ ] Push to default branch → server receives POST, signature validates, sync pipeline runs (`SyncPipeline`).
- [ ] Change connected repo → old hook removed, new hook created.
- [ ] Simulate Pro downgrade → hooks removed and DB fields cleared (today via `GitHubWebhookCleanup`; token source must still work with App auth after migration).
- [ ] Non-Pro: no hook created; manual sync still works as today.

---

## 10. Deliverables expected from the GitHub App work

1. **GitHub App** registered with correct **repository permissions** to manage repo webhooks (and any read scope needed for future token-based fetch).
2. **Installation flow** that yields a persistent **`installation_id`** per user or per repo connection.
3. **Service code** (language agnostic in this doc) that: mints JWT, exchanges for installation token, creates/deletes hooks with the **same** payload shape as `GitHubWebhookService.swift`.
4. **Documentation** of App ID, key handling (secrets manager), and which events/permissions were chosen.
5. **Coordination note** for backend engineers: Option A vs B, and updates to `GitHubWebhookCleanup` + `connectRepo` token source.

---

## 11. Quick reference — hook creation JSON (matches current server)

```json
{
  "name": "web",
  "config": {
    "url": "https://YOUR_PUBLIC_API/webhooks/github",
    "content_type": "json",
    "secret": "<32 bytes as lowercase hex string>"
  },
  "events": ["push"]
}
```

`secret` must be stored in `repo_connections.webhook_secret` and reused for `X-Hub-Signature-256` verification on inbound requests.

---

*This document is intentionally self-contained for handoff; align any server-side schema and OAuth scope changes with [`GITHUB_APP_PHASE2.md`](./GITHUB_APP_PHASE2.md) and the live code paths cited above.*
