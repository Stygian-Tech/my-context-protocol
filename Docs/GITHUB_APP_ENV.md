# GitHub App — environment variables

Configure these on the Vapor API when using **Phase 2** (installation access tokens for Pro webhooks).

| Variable | Required | Description |
|----------|----------|-------------|
| `GITHUB_APP_CLIENT_ID` | For Pro webhooks via App | OAuth **Client ID** from the GitHub App settings. Used as the JWT `iss` claim when authenticating as the app ([docs](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-json-web-token-jwt-for-a-github-app)). |
| `GITHUB_APP_PRIVATE_KEY` | For Pro webhooks via App | PEM private key (`-----BEGIN RSA PRIVATE KEY-----` …). For platforms that disallow multiline secrets, set `GITHUB_APP_PRIVATE_KEY_BASE64` instead (base64 of PEM bytes, no wrapping). |
| `GITHUB_APP_PRIVATE_KEY_BASE64` | Optional alternative | If set, overrides PEM parsing for `GITHUB_APP_PRIVATE_KEY`. |
| `GITHUB_APP_SLUG` | For install UX | URL slug of the GitHub App (e.g. `my-app` for `https://github.com/apps/my-app/installations/new`). |
| `GITHUB_APP_SETUP_CALLBACK_URL` | Install callback | Public URL GitHub redirects to after install (must match **Setup URL** in GitHub App settings). Typically `https://<api>/auth/github/app/callback`. |

**Already used (OAuth login / repo listing):**

- `GITHUB_CLIENT_ID`, `GITHUB_CLIENT_SECRET`, `GITHUB_OAUTH_REDIRECT_URI`

**Webhooks:**

- `WEBHOOK_BASE_URL` — unchanged; repo hooks POST to `{base}/webhooks/github`.

**Optional — App-level webhook** (install/revoke lifecycle):

| Variable | Description |
|----------|-------------|
| `GITHUB_APP_WEBHOOK_SECRET` | Secret from GitHub App **Webhook** settings. If set, `POST /webhooks/github-app` verifies `X-Hub-Signature-256` and processes `installation` / `github_app_authorization` events. Point the App’s **Webhook URL** at `https://<api-host>/webhooks/github-app` (same host you use for `WEBHOOK_BASE_URL` is typical). |

## GitHub App registration checklist

1. **Permissions (repository):** Contents: Read-only, Metadata: Read-only, and permissions needed to **create repository webhooks** (confirm current GitHub labels; may include Administration or Webhooks).
2. **Subscribe to events** (if using app webhook): `installation`, `installation_repositories`, `github_app_authorization` as needed.
3. **Setup URL:** Same host/path as `GITHUB_APP_SETUP_CALLBACK_URL` (user returns here with `installation_id`).
4. Generate and download a **private key**; store securely as env.

## Migration notes

- Pro users without `github_installation_id` on their `RepoConnection` still use the **user OAuth token** for hook CRUD until they complete **Install GitHub App** and reconnect or sync installation.
- API exposes `github_installation_configured` on repo connection and `suggested_github_app_install` on `GET /auth/me` when Pro + slug configured but installation not set.

## Sync and private repo fetch

- **`SyncPipeline`** (manual sync and repo `push` webhooks) resolves the GitHub API tarball token the same way as connect-repo webhook calls: when `github_installation_id` is set, it uses an **installation access token**; otherwise it uses the **user OAuth token** (with `repo` scope) from the connection or account.
- Org **SAML SSO** may still require members to authorize the OAuth app for org access on GitHub; that is enforced by GitHub, not this service.
