import Fluent

struct CreateToolsIndex: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("tools_index")
            .id()
            .field("skill_package_id", .uuid, .required, .references("skill_packages", "id", onDelete: .cascade))
            .field("tool_name", .string, .required)
            .field("schema_json", .string)
            .field("handler_type", .string, .required)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("tools_index").delete()
    }
}
