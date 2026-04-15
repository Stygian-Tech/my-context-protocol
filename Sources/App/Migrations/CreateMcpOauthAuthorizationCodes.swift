import Fluent

struct CreateMcpOauthAuthorizationCodes: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("mcp_oauth_authorization_codes")
            .id()
            .field("code_hash", .string, .required)
            .field("project_id", .uuid, .required, .references("projects", "id", onDelete: .cascade))
            .field("mcp_oauth_client_id", .uuid, .required, .references("mcp_oauth_clients", "id", onDelete: .cascade))
            .field("account_id", .uuid, .required, .references("accounts", "id", onDelete: .cascade))
            .field("redirect_uri", .string, .required)
            .field("scope", .string, .required)
            .field("code_challenge", .string, .required)
            .field("code_challenge_method", .string, .required)
            .field("expires_at", .datetime, .required)
            .field("consumed_at", .datetime)
            .field("created_at", .datetime)
            .unique(on: "code_hash")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("mcp_oauth_authorization_codes").delete()
    }
}
