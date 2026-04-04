import Foundation
import Vapor

struct ProjectResponse: Content {
    let id: String
    let account_id: String
    let name: String
    let slug: String
    let subdomain: String
    let created_at: String
    let custom_domain: String?
    let custom_domain_verified_at: String?
    /// Release currently serving MCP traffic when set.
    let active_release_id: String?
    /// Public MCP endpoint (`SAAS_MCP_URL_SCHEME`, host, `SAAS_MCP_PATH`). Nil if tenant base domain unset and no verified custom domain.
    let mcp_url: String?

    enum CodingKeys: String, CodingKey {
        case id, name, slug, subdomain
        case account_id = "account_id"
        case created_at = "created_at"
        case custom_domain = "custom_domain"
        case custom_domain_verified_at = "custom_domain_verified_at"
        case active_release_id = "active_release_id"
        case mcp_url = "mcp_url"
    }
}

struct CustomDomainResponse: Content {
    let hostname: String?
    let verified: Bool
    let verification_token: String?
    let instructions: String?

    enum CodingKeys: String, CodingKey {
        case hostname, verified, instructions
        case verification_token = "verification_token"
    }
}

struct RepoConnectionResponse: Content {
    let project_id: String
    let provider: String
    let repo_owner: String
    let repo_name: String
    let default_branch: String
    let auth_type: String
    let webhook_id: String?
    /// True when a GitHub App installation id is stored (Pro webhook / API calls can use installation token).
    let github_installation_configured: Bool

    enum CodingKeys: String, CodingKey {
        case provider, auth_type
        case project_id = "project_id"
        case repo_owner = "repo_owner"
        case repo_name = "repo_name"
        case default_branch = "default_branch"
        case webhook_id = "webhook_id"
        case github_installation_configured = "github_installation_configured"
    }
}

/// Returned with HTTP 409 when Pro webhooks require a GitHub App installation before `connect-repo` can proceed.
struct GitHubAppInstallRequiredResponse: Content {
    let reason: String
    let install_url: String
}

/// One repository the signed-in user can access (from GitHub `GET /user/repos`).
struct GithubRepoListItem: Content {
    let full_name: String
    let owner_login: String
    let name: String
    let default_branch: String
    let is_private: Bool

    enum CodingKeys: String, CodingKey {
        case full_name, name, default_branch
        case owner_login = "owner_login"
        case is_private = "is_private"
    }
}

struct ReleaseResponse: Content {
    let id: String
    let project_id: String
    let commit_sha: String
    let status: String
    let created_at: String
    let error_summary: String?
    let is_active: Bool
    let skill_body_changes_count: Int

    enum CodingKeys: String, CodingKey {
        case id, status
        case project_id = "project_id"
        case commit_sha = "commit_sha"
        case created_at = "created_at"
        case error_summary = "error_summary"
        case is_active = "is_active"
        case skill_body_changes_count = "skill_body_changes_count"
    }
}

struct ApiKeyResponse: Content {
    let id: String
    let project_id: String
    let name: String?
    let key_prefix: String
    let status: String
    let created_at: String
    let last_used_at: String?

    enum CodingKeys: String, CodingKey {
        case id, status
        case project_id = "project_id"
        case name
        case key_prefix = "key_prefix"
        case created_at = "created_at"
        case last_used_at = "last_used_at"
    }
}

struct ApiKeyCreateRequest: Content {
    let name: String?

    func normalizedName() throws -> String? {
        guard let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count <= 64 else {
            throw Abort(.badRequest, reason: "API key name must be 64 characters or fewer")
        }
        return trimmed
    }
}

struct ApiKeyCreateResponse: Content {
    let key: String
    let prefix: String
    let name: String?

    enum CodingKeys: String, CodingKey {
        case key, prefix, name
    }
}

struct ProjectCatalogTool: Content {
    let name: String
    let description: String?
    let input_schema_json: String?

    enum CodingKeys: String, CodingKey {
        case name, description
        case input_schema_json = "input_schema_json"
    }
}

struct ProjectCatalogResource: Content {
    let uri: String
    let name: String?
    let description: String?
    let mime_type: String?
    let use_when: [String]?
    let avoid_when: [String]?
    let failure_modes: [String]?
    let invoke_first: Bool?

    enum CodingKeys: String, CodingKey {
        case uri, name, description
        case mime_type = "mime_type"
        case use_when = "use_when"
        case avoid_when = "avoid_when"
        case failure_modes = "failure_modes"
        case invoke_first = "invoke_first"
    }
}

struct ProjectCatalogPrompt: Content {
    let name: String
    let description: String?
}

struct ProjectCatalogResponse: Content {
    let release_id: String?
    let release_status: String?
    let mcp_url: String?
    let tools: [ProjectCatalogTool]
    let resources: [ProjectCatalogResource]
    let prompts: [ProjectCatalogPrompt]

    enum CodingKeys: String, CodingKey {
        case tools, resources, prompts
        case release_id = "release_id"
        case release_status = "release_status"
        case mcp_url = "mcp_url"
    }
}

/// PATCH body fragment for SKILL routing fields (mirrors front matter; persisted in `routing_rules`).
struct CompiledSkillRoutingPatch: Content {
    var use_when: [String]?
    var avoid_when: [String]?
    var failure_modes: [String]?
    var invoke_first: Bool?

    enum CodingKeys: String, CodingKey {
        case use_when = "use_when"
        case avoid_when = "avoid_when"
        case failure_modes = "failure_modes"
        case invoke_first = "invoke_first"
    }
}

struct CompiledSkillResponse: Content {
    let id: String
    let release_id: String
    let skill_package_id: String
    let path: String
    let name: String
    let summary: String?
    /// SKILL.md body used for MCP tool/resource/prompt content.
    let skill_body: String?
    /// MCP `inputSchema` / metadata JSON for this skill’s capability (from `capability_defs.schema_json`).
    let schema_json: String?
    /// Whether the synced file included a closed YAML `---` block (false when name was inferred from the parent folder).
    let yaml_frontmatter_present: Bool
    let exposure_type: String
    let risk_level: String
    let repo_specific: Bool
    let status: String
    /// From `routing_rules` — comma lists in SKILL become arrays; surfaced on MCP resources when `exposure_type` is `resource`.
    let use_when: [String]
    let avoid_when: [String]
    let failure_modes: [String]
    let invoke_first: Bool
    /// Unified diff vs prior release when the SKILL body changed.
    let body_diff_unified: String?
    let body_diff_prior_release_id: String?

    enum CodingKeys: String, CodingKey {
        case id, path, name, summary
        case release_id = "release_id"
        case skill_package_id = "skill_package_id"
        case skill_body = "skill_body"
        case schema_json = "schema_json"
        case yaml_frontmatter_present = "yaml_frontmatter_present"
        case exposure_type = "exposure_type"
        case risk_level = "risk_level"
        case repo_specific = "repo_specific"
        case use_when = "use_when"
        case avoid_when = "avoid_when"
        case failure_modes = "failure_modes"
        case invoke_first = "invoke_first"
        case status = "status"
        case body_diff_unified = "body_diff_unified"
        case body_diff_prior_release_id = "body_diff_prior_release_id"
    }
}

struct RequestLogResponse: Content {
    let id: String
    let project_id: String
    let release_id: String?
    let timestamp: String
    let client_id: String?
    let method: String
    let latency_ms: Int?
    let status: Int
    let error_code: String?
    let error_message: String?

    enum CodingKeys: String, CodingKey {
        case id, method
        case project_id = "project_id"
        case release_id = "release_id"
        case timestamp = "timestamp"
        case client_id = "client_id"
        case latency_ms = "latency_ms"
        case status = "status"
        case error_code = "error_code"
        case error_message = "error_message"
    }
}

struct ReleaseValidationResponse: Content {
    let is_valid: Bool
    let errors: [ValidationErrorEntry]
    let warnings: [ValidationErrorEntry]

    enum CodingKeys: String, CodingKey {
        case is_valid = "is_valid"
        case errors
        case warnings
    }
}

// MARK: - Dashboard summaries

struct DashboardMethodCount: Content {
    let method: String
    let count: Int
}

struct DashboardProjectTraffic: Content {
    let project_id: String
    let project_name: String
    let request_count: Int

    enum CodingKeys: String, CodingKey {
        case project_id = "project_id"
        case project_name = "project_name"
        case request_count = "request_count"
    }
}

struct AccountDashboardSummaryResponse: Content {
    let total_requests: Int
    let requests_last_24h: Int
    let requests_last_7d: Int
    /// HTTP status < 400; computed from `metrics_sample_size_last_7d` newest logs (see that field).
    let success_rate_last_7d: Double?
    let metrics_sample_size_last_7d: Int
    let avg_latency_ms_last_7d: Double?
    let p95_latency_ms_last_7d: Int?
    let projects_total: Int
    let projects_with_active_release: Int
    let active_tools_total: Int
    let active_resources_total: Int
    let active_prompts_total: Int
    let method_breakdown_last_7d: [DashboardMethodCount]
    let top_projects_last_7d: [DashboardProjectTraffic]

    enum CodingKeys: String, CodingKey {
        case total_requests = "total_requests"
        case requests_last_24h = "requests_last_24h"
        case requests_last_7d = "requests_last_7d"
        case success_rate_last_7d = "success_rate_last_7d"
        case metrics_sample_size_last_7d = "metrics_sample_size_last_7d"
        case avg_latency_ms_last_7d = "avg_latency_ms_last_7d"
        case p95_latency_ms_last_7d = "p95_latency_ms_last_7d"
        case projects_total = "projects_total"
        case projects_with_active_release = "projects_with_active_release"
        case active_tools_total = "active_tools_total"
        case active_resources_total = "active_resources_total"
        case active_prompts_total = "active_prompts_total"
        case method_breakdown_last_7d = "method_breakdown_last_7d"
        case top_projects_last_7d = "top_projects_last_7d"
    }
}

struct ProjectDashboardSummaryResponse: Content {
    let project_id: String
    let total_requests: Int
    let requests_last_24h: Int
    let requests_last_7d: Int
    let success_rate_last_7d: Double?
    let metrics_sample_size_last_7d: Int
    let avg_latency_ms_last_7d: Double?
    let p95_latency_ms_last_7d: Int?
    let method_breakdown_last_7d: [DashboardMethodCount]
    let active_release_id: String?
    let active_commit_sha: String?
    let active_release_status: String?
    let active_tools: Int
    let active_resources: Int
    let active_prompts: Int

    enum CodingKeys: String, CodingKey {
        case project_id = "project_id"
        case total_requests = "total_requests"
        case requests_last_24h = "requests_last_24h"
        case requests_last_7d = "requests_last_7d"
        case success_rate_last_7d = "success_rate_last_7d"
        case metrics_sample_size_last_7d = "metrics_sample_size_last_7d"
        case avg_latency_ms_last_7d = "avg_latency_ms_last_7d"
        case p95_latency_ms_last_7d = "p95_latency_ms_last_7d"
        case method_breakdown_last_7d = "method_breakdown_last_7d"
        case active_release_id = "active_release_id"
        case active_commit_sha = "active_commit_sha"
        case active_release_status = "active_release_status"
        case active_tools = "active_tools"
        case active_resources = "active_resources"
        case active_prompts = "active_prompts"
    }
}

// MARK: - Dashboard timeseries

struct DashboardTimeseriesBucketDTO: Content {
    let label: String
    let start: String
    let end: String
    let request_count: Int
    let success_count: Int
    let avg_latency_ms: Double?

    enum CodingKeys: String, CodingKey {
        case label, start, end
        case request_count = "request_count"
        case success_count = "success_count"
        case avg_latency_ms = "avg_latency_ms"
    }
}

struct AccountDashboardTimeseriesResponse: Content {
    let range_key: String
    let range_start: String
    let range_end: String
    let buckets: [DashboardTimeseriesBucketDTO]

    enum CodingKeys: String, CodingKey {
        case range_key = "range_key"
        case range_start = "range_start"
        case range_end = "range_end"
        case buckets
    }
}

struct ProjectDashboardTimeseriesResponse: Content {
    let project_id: String
    let range_key: String
    let range_start: String
    let range_end: String
    let buckets: [DashboardTimeseriesBucketDTO]

    enum CodingKeys: String, CodingKey {
        case project_id = "project_id"
        case range_key = "range_key"
        case range_start = "range_start"
        case range_end = "range_end"
        case buckets
    }
}

/// Platform-wide dashboard timeseries for admins; backed by hourly rollup (`admin_analytics_hourly`).
struct AdminDashboardTimeseriesResponse: Content {
    let range_key: String
    let range_start: String
    let range_end: String
    let buckets: [DashboardTimeseriesBucketDTO]
    /// Latest `updated_at` from rollup rows contributing to this response, if any.
    let rollup_updated_at: String?
    let data_source_note: String

    enum CodingKeys: String, CodingKey {
        case range_key = "range_key"
        case range_start = "range_start"
        case range_end = "range_end"
        case buckets
        case rollup_updated_at = "rollup_updated_at"
        case data_source_note = "data_source_note"
    }
}

struct ValidationErrorEntry: Content {
    let path: String
    let message: String
}
