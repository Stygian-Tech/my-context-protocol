import Fluent

struct CreateRepoConnections: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("repo_connections")
            .id()
            .field("project_id", .uuid, .required, .references("projects", "id", onDelete: .cascade))
            .field("provider", .string, .required)
            .field("repo_owner", .string, .required)
            .field("repo_name", .string, .required)
            .field("default_branch", .string, .required)
            .field("auth_type", .string, .required)
            .field("token_ref", .string)
            .field("webhook_id", .string)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("repo_connections").delete()
    }
}
