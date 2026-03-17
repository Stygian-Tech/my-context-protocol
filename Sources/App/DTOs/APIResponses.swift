import Foundation
import Vapor

struct ProjectResponse: Content {
    let id: String
    let account_id: String
    let name: String
    let slug: String
    let subdomain: String
    let created_at: String

    enum CodingKeys: String, CodingKey {
        case id, name, slug, subdomain
        case account_id = "account_id"
        case created_at = "created_at"
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

    enum CodingKeys: String, CodingKey {
        case provider, auth_type
        case project_id = "project_id"
        case repo_owner = "repo_owner"
        case repo_name = "repo_name"
        case default_branch = "default_branch"
        case webhook_id = "webhook_id"
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
