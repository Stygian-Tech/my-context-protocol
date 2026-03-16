import Fluent

struct CreateSkillPackages: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("skill_packages")
            .id()
            .field("release_id", .uuid, .required, .references("releases", "id", onDelete: .cascade))
            .field("path", .string, .required)
            .field("name", .string, .required)
            .field("description", .string)
            .field("hash", .string)
            .field("validation_status", .string, .required)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("skill_packages").delete()
    }
}
