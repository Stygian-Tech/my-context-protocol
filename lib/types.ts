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
  /** Release currently serving MCP traffic. */
  active_release_id?: string | null;
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
  is_active?: boolean;
  skill_body_changes_count?: number;
  /** From `GET /projects/:id/releases` — skills with blocking MCP metadata (same rules as MCP Metadata dialog). */
  mcp_metadata_blocking_skills?: number;
  mcp_metadata_warning_skills?: number;
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
  /** From SKILL.md / routing metadata; surfaced in MCP `resources/list` as `use_when`. */
  use_when?: string[] | null;
  avoid_when?: string[] | null;
  failure_modes?: string[] | null;
  invoke_first?: boolean | null;
}

export interface ProjectCatalogPrompt {
  name: string;
  description?: string | null;
}

export interface ProjectCatalog {
  release_id?: string | null;
  release_status?: string | null;
  mcp_url?: string | null;
  /** Same markdown returned by MCP `tools/call` for `mycontext:catalog`. */
  catalog_markdown: string;
  /** Auto-generated catalog from the active release (ignores custom override). Omitted on older API responses. */
  catalog_markdown_generated?: string;
  /** Custom markdown when set; then `catalog_markdown` matches this. */
  catalog_markdown_override?: string | null;
  tools: ProjectCatalogTool[];
  resources: ProjectCatalogResource[];
  prompts: ProjectCatalogPrompt[];
}

/** Response from PATCH `/projects/:id/catalog-markdown`. */
export interface ProjectCatalogMarkdownUpdate {
  catalog_markdown: string;
  catalog_markdown_generated: string;
  catalog_markdown_override?: string | null;
}

export interface ApiKey {
  id: string;
  project_id: string;
  name?: string | null;
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
  /** Non-blocking ingest notices (e.g. missing YAML front matter). */
  warnings?: ValidationErrorEntry[];
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
  /** False when the repo file had no YAML `---` block (name inferred from parent folder). */
  yaml_frontmatter_present?: boolean;
  exposure_type: "tool" | "resource" | "prompt" | string;
  risk_level: string;
  repo_specific: boolean;
  status: string;
  /** From SKILL front matter / routing_rules; MCP resource hints when exposure is `resource`. */
  use_when?: string[];
  avoid_when?: string[];
  failure_modes?: string[];
  invoke_first?: boolean;
  /** Unified line diff vs prior release when SKILL body changed since last active release. */
  body_diff_unified?: string | null;
  body_diff_prior_release_id?: string | null;
}

export interface DashboardMethodCount {
  method: string;
  count: number;
}

export interface DashboardProjectTraffic {
  project_id: string;
  project_name: string;
  request_count: number;
}

export interface AccountDashboardSummary {
  total_requests: number;
  requests_last_24h: number;
  requests_last_7d: number;
  success_rate_last_7d: number | null;
  metrics_sample_size_last_7d: number;
  avg_latency_ms_last_7d: number | null;
  p95_latency_ms_last_7d: number | null;
  projects_total: number;
  projects_with_active_release: number;
  active_tools_total: number;
  active_resources_total: number;
  active_prompts_total: number;
  method_breakdown_last_7d: DashboardMethodCount[];
  top_projects_last_7d: DashboardProjectTraffic[];
}

export interface ProjectDashboardSummary {
  project_id: string;
  total_requests: number;
  requests_last_24h: number;
  requests_last_7d: number;
  success_rate_last_7d: number | null;
  metrics_sample_size_last_7d: number;
  avg_latency_ms_last_7d: number | null;
  p95_latency_ms_last_7d: number | null;
  method_breakdown_last_7d: DashboardMethodCount[];
  active_release_id?: string | null;
  active_commit_sha?: string | null;
  active_release_status?: string | null;
  active_tools: number;
  active_resources: number;
  active_prompts: number;
}

export type AppEnv = "local" | "dev" | "prod";

export interface User {
  id: string;
  email?: string;
  login?: string;
  avatar_url?: string;
  plan: "free" | "pro";
  /** Platform admin (aggregate tools + grants). */
  is_admin?: boolean;
  /** Server env allowlist (`INTERNAL_PRO_GITHUB_*`); not a Stripe subscription. */
  internal_pro_bypass?: boolean;
  /** Stripe Customer on file — Customer Portal works. */
  can_manage_subscription?: boolean;
  /** Backend `APP_ENV` from `/auth/me`. */
  app_env?: AppEnv;
  /** True when API applies non-production Pro/rate-limit bypasses. */
  non_production_bypasses?: boolean;
}
