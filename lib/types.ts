export type ReleaseStatus = "pending" | "ready" | "failed";

export interface Project {
  id: string;
  account_id: string;
  name: string;
  slug: string;
  subdomain: string;
  created_at: string;
  custom_domain?: string | null;
  custom_domain_verified_at?: string | null;
  /** Full MCP endpoint URL from the API (scheme + host + path). */
  mcp_url?: string | null;
}

export interface RepoConnection {
  project_id: string;
  provider: string;
  repo_owner: string;
  repo_name: string;
  default_branch: string;
  auth_type: string;
  webhook_id?: string | null;
}

/** From `GET /github/repos` (GitHub repos the OAuth token can access). */
export interface GithubRepoListItem {
  full_name: string;
  owner_login: string;
  name: string;
  default_branch: string;
  is_private: boolean;
}

export interface Release {
  id: string;
  project_id: string;
  commit_sha: string;
  status: ReleaseStatus;
  created_at: string;
  error_summary?: string | null;
}

export interface SkillPackage {
  id: string;
  release_id: string;
  path: string;
  name: string;
  description?: string | null;
  hash: string;
  validation_status: string;
}

export interface ApiKey {
  id: string;
  project_id: string;
  key_prefix: string;
  status: string;
  created_at: string;
  last_used_at?: string | null;
}

export interface RequestLog {
  id: string;
  project_id: string;
  release_id?: string | null;
  timestamp: string;
  client_id?: string | null;
  method: string;
  latency_ms?: number | null;
  status: number;
  error_code?: string | null;
}

export type AppEnv = "local" | "dev" | "prod";

export interface User {
  id: string;
  email?: string;
  login?: string;
  avatar_url?: string;
  plan: "free" | "pro";
  /** Server env allowlist (`INTERNAL_PRO_GITHUB_*`); not a Stripe subscription. */
  internal_pro_bypass?: boolean;
  /** Stripe Customer on file — Customer Portal works. */
  can_manage_subscription?: boolean;
  /** Backend `APP_ENV` from `/auth/me`. */
  app_env?: AppEnv;
  /** True when API applies non-production Pro/rate-limit bypasses. */
  non_production_bypasses?: boolean;
}
