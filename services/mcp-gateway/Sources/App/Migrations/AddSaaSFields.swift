import Fluent

/// Adds webhook_secret to repo_connections and github_token_encrypted to accounts for SaaS.
struct AddSaaSFields: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("repo_connections")
            .field("webhook_secret", .string)
            .update()
        try await database.schema("repo_connections")
            .field("token_encrypted", .string)
            .update()

        try await database.schema("accounts")
            .field("github_token_encrypted", .string)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("repo_connections").deleteField("webhook_secret").update()
        try await database.schema("repo_connections").deleteField("token_encrypted").update()
        try await database.schema("accounts").deleteField("github_token_encrypted").update()
    }
}
