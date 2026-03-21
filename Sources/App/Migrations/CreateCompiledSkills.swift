import Fluent

struct CreateCompiledSkills: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("compiled_skills")
            .id()
            .field("release_id", .uuid, .required, .references("releases", "id", onDelete: .cascade))
            .field("skill_package_id", .uuid, .required, .references("skill_packages", "id", onDelete: .cascade))
            .field("path", .string, .required)
            .field("name", .string, .required)
            .field("summary", .string)
            .field("exposure_type", .string, .required)
            .field("risk_level", .string, .required)
            .field("repo_specific", .bool, .required)
            .field("status", .string, .required)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("compiled_skills").delete()
    }
}
