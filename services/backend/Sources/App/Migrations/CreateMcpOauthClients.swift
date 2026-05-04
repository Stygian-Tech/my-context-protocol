import Fluent

struct CreateMcpOauthClients: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("mcp_oauth_clients")
            .id()
            .field("public_client_id", .string, .required)
            .field("client_secret_hash", .string)
            .field("is_confidential", .bool, .required)
            .field("redirect_uris_json", .string, .required)
            .field("allowed_grants", .string, .required)
            .field("status", .string, .required)
            .field("created_at", .datetime)
            .unique(on: "public_client_id")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("mcp_oauth_clients").delete()
    }
}
