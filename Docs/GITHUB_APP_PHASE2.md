# Phase 2: GitHub App (epic)

Today the product uses a **GitHub OAuth App** with `repo` scope and **per-repository webhooks** created via the user token. Pro tier gates webhook creation; Free uses manual sync only.

## Goals for a first-class GitHub App

1. **Installation-based access** — Users install the GitHub App on orgs/repos; the backend uses **installation access tokens** (short-lived) instead of long-lived user PATs where possible.
2. **Narrower OAuth** — Login can stay on GitHub OAuth for identity, while repo access is delegated to the App installation.
3. **Webhooks** — Either keep **repo webhooks** created with installation token, or subscribe to **App-level** `push` / `repository` events and route by repo name (fewer hooks, easier org-wide coverage).
4. **Schema** — Store `installation_id` (per connection or per account), handle `installation_repositories` sync, and process `github_app_authorization` revocation.

## Suggested implementation order

1. Register the GitHub App (permissions: Contents read, Metadata read, Webhooks or single “Subscribe to events” as needed).
2. Add OAuth / callback for “Install app” flow; persist `installation_id` on `RepoConnection` or `Account`.
3. Replace `GitHubWebhookService` token source: fetch installation token from `POST /app/installations/{id}/access_tokens`.
4. Migrate existing Pro users: “Reconnect repo” flow to bind installation.
5. Optionally reduce `repo` OAuth scope for users who only install the App.

## References

- [Creating a GitHub App](https://docs.github.com/en/apps/creating-github-apps)
- [Authenticating as a GitHub App installation](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/authenticating-as-a-github-app-installation)
