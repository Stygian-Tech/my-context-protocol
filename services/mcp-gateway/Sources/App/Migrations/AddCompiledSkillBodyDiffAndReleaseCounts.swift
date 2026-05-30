import Fluent

struct AddCompiledSkillBodyDiffAndReleaseCounts: AsyncMigration {
    func prepare(on database: Database) async throws {
        // SQLite allows at most one ADD COLUMN per ALTER; Fluent otherwise emits invalid SQL.
        try await database.schema("compiled_skills").field("body_diff_unified", .string).update()
        try await database.schema("compiled_skills")
            .field("body_diff_prior_release_id", .uuid, .references("releases", "id", onDelete: .setNull))
            .update()

        try await database.schema("releases")
            .field("skill_body_changes_count", .int, .required, .sql(.default(0)))
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("compiled_skills").deleteField("body_diff_prior_release_id").update()
        try await database.schema("compiled_skills").deleteField("body_diff_unified").update()

        try await database.schema("releases")
            .deleteField("skill_body_changes_count")
            .update()
    }
}
