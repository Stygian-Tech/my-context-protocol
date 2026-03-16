import Fluent

struct CreateApiKeys: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("api_keys")
            .id()
            .field("project_id", .uuid, .required, .references("projects", "id", onDelete: .cascade))
            .field("key_prefix", .string, .required)
            .field("key_hash", .string, .required)
            .field("status", .string, .required)
            .field("created_at", .datetime)
            .field("last_used_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("api_keys").delete()
    }
}
