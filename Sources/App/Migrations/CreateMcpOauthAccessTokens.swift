import Fluent

struct CreateMcpOauthAccessTokens: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("mcp_oauth_access_tokens")
            .id()
            .field("token_hash", .string, .required)
            .field("project_id", .uuid, .required, .references("projects", "id", onDelete: .cascade))
            .field("mcp_oauth_client_id", .uuid, .required, .references("mcp_oauth_clients", "id", onDelete: .cascade))
            .field("account_id", .uuid, .references("accounts", "id", onDelete: .cascade))
            .field("subject_type", .string, .required)
            .field("scope", .string, .required)
            .field("expires_at", .datetime, .required)
            .field("revoked_at", .datetime)
            .field("created_at", .datetime)
            .unique(on: "token_hash")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("mcp_oauth_access_tokens").delete()
    }
}
