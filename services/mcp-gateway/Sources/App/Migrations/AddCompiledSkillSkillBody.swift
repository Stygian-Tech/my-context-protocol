import Fluent

struct AddCompiledSkillSkillBody: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("compiled_skills")
            .field("skill_body", .string)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("compiled_skills")
            .deleteField("skill_body")
            .update()
    }
}
