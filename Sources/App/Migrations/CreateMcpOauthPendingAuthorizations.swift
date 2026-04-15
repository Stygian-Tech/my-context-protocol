import Fluent

struct CreateMcpOauthPendingAuthorizations: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("mcp_oauth_pending_authorizations")
            .id()
            .field("project_id", .uuid, .required, .references("projects", "id", onDelete: .cascade))
            .field("mcp_oauth_client_id", .uuid, .required, .references("mcp_oauth_clients", "id", onDelete: .cascade))
            .field("redirect_uri", .string, .required)
            .field("state", .string, .required)
            .field("scope", .string, .required)
            .field("code_challenge", .string, .required)
            .field("code_challenge_method", .string, .required)
            .field("expires_at", .datetime, .required)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("mcp_oauth_pending_authorizations").delete()
    }
}
