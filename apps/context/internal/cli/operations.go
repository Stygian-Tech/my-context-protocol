package cli

// Operation describes a supported application operation. Paths match the Gateway
// routes; colon-prefixed parameters are supplied through CLI flags.
type Operation struct {
	Name        string `json:"name"`
	Method      string `json:"method"`
	Path        string `json:"path"`
	Description string `json:"description"`
}

// Operations is the complete application management surface. Webhooks, internal
// infrastructure endpoints, and browser OAuth callbacks are intentionally excluded.
var Operations = []Operation{
	{"health", "GET", "/health", "Check Gateway health"},
	{"auth me", "GET", "/auth/me", "Show the authenticated account"},
	{"auth logout", "POST", "/auth/logout", "Invalidate the current session"},
	{"dashboard summary", "GET", "/dashboard/summary", "Show account dashboard summary"},
	{"dashboard timeseries", "GET", "/dashboard/timeseries", "Show account dashboard timeseries"},
	{"projects list", "GET", "/projects", "List owned projects"},
	{"projects create", "POST", "/projects", "Create a project with name and slug"},
	{"projects get", "GET", "/projects/:id", "Show a project"},
	{"projects update", "PATCH", "/projects/:id", "Update a project display name"},
	{"projects set-active", "POST", "/projects/:id/set-active", "Select the active project for the account"},
	{"projects summary", "GET", "/projects/:id/dashboard/summary", "Show project dashboard summary"},
	{"projects timeseries", "GET", "/projects/:id/dashboard/timeseries", "Show project dashboard timeseries"},
	{"catalog get", "GET", "/projects/:id/catalog", "Show active release capabilities and catalog markdown"},
	{"catalog update", "PATCH", "/projects/:id/catalog-markdown", "Update custom catalog markdown"},
	{"repos connection", "GET", "/projects/:id/repo-connection", "Show the project repository connection"},
	{"repos connect", "POST", "/projects/:id/connect-repo", "Connect a GitHub repository and branch"},
	{"projects sync", "POST", "/projects/:id/sync", "Trigger repository synchronization"},
	{"releases list", "GET", "/projects/:id/releases", "List project releases"},
	{"releases activate", "POST", "/projects/:id/releases/:releaseId/activate", "Activate a project release"},
	{"releases validation", "GET", "/projects/:id/releases/:releaseId/validation", "Show release validation results"},
	{"skills list", "GET", "/projects/:id/releases/:releaseId/compiled-skills", "List compiled release skills"},
	{"skills update", "PATCH", "/projects/:id/releases/:releaseId/compiled-skills/:compiledSkillId", "Update compiled skill content, MCP metadata, routing, and runtime overrides"},
	{"skills writeback", "POST", "/projects/:id/releases/:releaseId/compiled-skills/:compiledSkillId/writeback", "Create a branch and draft GitHub pull request for skill metadata"},
	{"skills usage", "GET", "/projects/:id/skill-usage", "Show paginated retained per-skill usage analytics"},
	{"runtime get", "GET", "/projects/:id/skill-runtime", "Show runtime settings, assignments, and recent events"},
	{"runtime update", "PATCH", "/projects/:id/skill-runtime", "Update runtime settings, assignments, feedback permissions, and telemetry consent"},
	{"keys list", "GET", "/projects/:id/api-keys", "List active API keys, optionally including revoked keys"},
	{"keys create", "POST", "/projects/:id/api-keys", "Create an MCP API key; the full key is returned once"},
	{"keys update", "PATCH", "/projects/:id/api-keys/:keyId", "Rename an active API key"},
	{"keys revoke", "DELETE", "/projects/:id/api-keys/:keyId", "Revoke an MCP API key"},
	{"logs list", "GET", "/projects/:id/request-logs", "List request logs using limit and offset pagination"},
	{"domains get", "GET", "/projects/:id/custom-domain", "Show custom domain DNS and TLS status"},
	{"domains set", "POST", "/projects/:id/custom-domain", "Provision a custom domain"},
	{"domains verify", "POST", "/projects/:id/custom-domain/verify", "Verify project ownership, routing DNS, and TLS status"},
	{"billing checkout", "POST", "/billing/checkout-session", "Create a Pro billing checkout URL"},
	{"billing portal", "POST", "/billing/portal-session", "Create a billing portal URL"},
	{"github repos", "GET", "/github/repos", "List accessible GitHub repositories"},
	{"github install", "GET", "/auth/github/app/install", "Start GitHub App installation for a project"},
	{"admin metrics", "GET", "/admin/metrics", "Show aggregate platform metrics (administrator required)"},
	{"admin timeseries", "GET", "/admin/timeseries", "Show platform analytics timeseries (administrator required)"},
	{"admin rollup-refresh", "POST", "/admin/analytics/rollup-refresh", "Refresh analytics rollups (administrator required)"},
	{"admin lookup", "POST", "/admin/lookup", "Look up account flags by GitHub login, GitHub ID, or email (administrator required)"},
	{"admin privileged-accounts", "GET", "/admin/privileged-accounts", "List privileged accounts (administrator required)"},
	{"admin account-flags", "POST", "/admin/account-flags", "Update account administrator and paywall bypass flags (administrator required)"},
}
