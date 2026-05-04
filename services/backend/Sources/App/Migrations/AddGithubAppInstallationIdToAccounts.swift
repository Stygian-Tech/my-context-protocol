import Fluent

struct AddGithubAppInstallationIdToAccounts: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("accounts")
            .field("github_app_installation_id", .int64)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("accounts").deleteField("github_app_installation_id").update()
    }
}
