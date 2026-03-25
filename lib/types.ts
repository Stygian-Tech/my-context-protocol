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

export interface ProjectCatalogTool {
  name: string;
  description?: string | null;
  input_schema_json?: string | null;
}

export interface ProjectCatalogResource {
  uri: string;
  name?: string | null;
  description?: string | null;
  mime_type?: string | null;
}

export interface ProjectCatalogPrompt {
  name: string;
  description?: string | null;
}

export interface ProjectCatalog {
  release_id?: string | null;
  release_status?: string | null;
  mcp_url?: string | null;
  tools: ProjectCatalogTool[];
  resources: ProjectCatalogResource[];
  prompts: ProjectCatalogPrompt[];
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
  /** JSON-RPC error message or other detail when present */
  error_message?: string | null;
}

export interface ValidationErrorEntry {
  path: string;
  message: string;
}

export interface ReleaseValidationReport {
  is_valid: boolean;
  errors: ValidationErrorEntry[];
}

export interface CompiledSkill {
  id: string;
  release_id: string;
  skill_package_id: string;
  path: string;
  name: string;
  summary?: string | null;
  /** SKILL.md body — tool/resource/prompt content over MCP. */
  skill_body?: string | null;
  /** Capability metadata / tool inputSchema JSON from the compiler or your edits. */
  schema_json?: string | null;
  exposure_type: "tool" | "resource" | "prompt" | string;
  risk_level: string;
  repo_specific: boolean;
  status: string;
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
