import Fluent

struct CreateReleases: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("releases")
            .id()
            .field("project_id", .uuid, .required, .references("projects", "id", onDelete: .cascade))
            .field("commit_sha", .string, .required)
            .field("status", .string, .required)
            .field("created_at", .datetime)
            .field("error_summary", .string)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("releases").delete()
    }
}
