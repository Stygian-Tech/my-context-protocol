import Fluent

struct CreateAuthConfigs: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("auth_configs")
            .id()
            .field("project_id", .uuid, .required, .references("projects", "id", onDelete: .cascade))
            .field("mode", .string, .required)
            .field("settings_json", .string)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("auth_configs").delete()
    }
}
