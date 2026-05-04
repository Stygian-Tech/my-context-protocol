import Fluent

struct CreateRoutingRules: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("routing_rules")
            .id()
            .field("compiled_skill_id", .uuid, .required, .references("compiled_skills", "id", onDelete: .cascade))
            .field("use_when_json", .string)
            .field("avoid_when_json", .string)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("routing_rules").delete()
    }
}
