import Fluent

/// Short-lived row keyed by UUID `state` for GitHub App install (survives multi-instance in-memory sessions).
struct CreateGitHubAppInstallIntents: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("github_app_install_intents")
            .id()
            .field("project_id", .uuid, .required, .references("projects", "id", onDelete: .cascade))
            .field("account_id", .uuid, .required, .references("accounts", "id", onDelete: .cascade))
            .field("return_to", .string)
            .field("owner", .string)
            .field("repo", .string)
            .field("expires_at", .datetime, .required)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("github_app_install_intents").delete()
    }
}
