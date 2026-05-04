import Fluent

struct CreateCapabilityDefs: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("capability_defs")
            .id()
            .field("compiled_skill_id", .uuid, .required, .references("compiled_skills", "id", onDelete: .cascade))
            .field("capability_name", .string, .required)
            .field("type", .string, .required)
            .field("schema_json", .string)
            .field("side_effect_level", .string, .required)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("capability_defs").delete()
    }
}
