import Fluent

struct AddGithubInstallationToRepoConnections: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("repo_connections")
            .field("github_installation_id", .int64)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("repo_connections").deleteField("github_installation_id").update()
    }
}
