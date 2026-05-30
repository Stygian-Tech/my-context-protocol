import Fluent

struct CreateOAuthHandoffTokens: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("oauth_handoff_tokens")
            .id()
            .field("token", .string, .required)
            .field("account_id", .uuid, .required, .references("accounts", "id", onDelete: .cascade))
            .field("expires_at", .datetime, .required)
            .field("created_at", .datetime)
            .unique(on: "token")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("oauth_handoff_tokens").delete()
    }
}
