import Fluent

struct CreateProjects: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("projects")
            .id()
            .field("account_id", .uuid, .required, .references("accounts", "id", onDelete: .cascade))
            .field("name", .string, .required)
            .field("slug", .string, .required)
            .field("subdomain", .string)
            .field("active_release_id", .uuid)
            .field("created_at", .datetime)
            .unique(on: "slug")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("projects").delete()
    }
}
