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
    /// Public MCP endpoint (`SAAS_MCP_URL_SCHEME`, host, `SAAS_MCP_PATH`). Nil if tenant base domain unset and no verified custom domain.
    let mcp_url: String?

    enum CodingKeys: String, CodingKey {
        case id, name, slug, subdomain
        case account_id = "account_id"
        case created_at = "created_at"
        case custom_domain = "custom_domain"
        case custom_domain_verified_at = "custom_domain_verified_at"
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

    enum CodingKeys: String, CodingKey {
        case id, status
        case project_id = "project_id"
        case commit_sha = "commit_sha"
        case created_at = "created_at"
        case error_summary = "error_summary"
    }
}

struct ApiKeyResponse: Content {
    let id: String
    let project_id: String
    let key_prefix: String
    let status: String
    let created_at: String
    let last_used_at: String?

    enum CodingKeys: String, CodingKey {
        case id, status
        case project_id = "project_id"
        case key_prefix = "key_prefix"
        case created_at = "created_at"
        case last_used_at = "last_used_at"
    }
}

struct ApiKeyCreateResponse: Content {
    let key: String
    let prefix: String

    enum CodingKeys: String, CodingKey {
        case key, prefix
    }
}

struct CompiledSkillResponse: Content {
    let id: String
    let release_id: String
    let skill_package_id: String
    let path: String
    let name: String
    let summary: String?
    let exposure_type: String
    let risk_level: String
    let repo_specific: Bool
    let status: String

    enum CodingKeys: String, CodingKey {
        case id, path, name, summary
        case release_id = "release_id"
        case skill_package_id = "skill_package_id"
        case exposure_type = "exposure_type"
        case risk_level = "risk_level"
        case repo_specific = "repo_specific"
        case status = "status"
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

    enum CodingKeys: String, CodingKey {
        case id, method
        case project_id = "project_id"
        case release_id = "release_id"
        case timestamp = "timestamp"
        case client_id = "client_id"
        case latency_ms = "latency_ms"
        case status = "status"
        case error_code = "error_code"
    }
}
