import Fluent

struct AddYamlFrontmatterPresentToCompiledSkills: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("compiled_skills")
            .field("yaml_frontmatter_present", .bool, .required, .sql(.default(true)))
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("compiled_skills")
            .deleteField("yaml_frontmatter_present")
            .update()
    }
}
