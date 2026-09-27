import Fluent
import SQLKit

/// Additive corrections for the portable Agent Skills runtime. Existing columns and tables are
/// intentionally retained so a rolling deployment can read releases produced by either version.
struct HardenPortableSkillRuntime: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(CompiledSkill.schema)
            .field("source_policy_json", .string)
            .update()
        try await database.schema(CompiledSkill.schema)
            .field("source_policy_base_checksum", .string)
            .update()
        try await database.schema(CompiledSkill.schema)
            .field("source_policy_stale", .bool, .required, .sql(.default(false)))
            .update()

        try await database.schema(SkillRuntimeOverride.schema)
            .field("base_checksum", .string)
            .update()
        try await database.schema(SkillRuntimeOverride.schema)
            .field("is_stale", .bool, .required, .sql(.default(false)))
            .update()
        if let sql = database as? any SQLDatabase {
            try await sql.raw(
                """
                CREATE UNIQUE INDEX IF NOT EXISTS uq_skill_overrides_project_fallback
                ON skill_runtime_overrides(project_id, skill_id, scope)
                WHERE repo_connection_id IS NULL
                """
            ).run()
            try await sql.raw(
                """
                CREATE UNIQUE INDEX IF NOT EXISTS uq_skill_overrides_repository
                ON skill_runtime_overrides(project_id, repo_connection_id, skill_id, scope)
                WHERE repo_connection_id IS NOT NULL
                """
            ).run()
        }

        // A previous binary can continue inserting rows during a rolling deployment, but the
        // legacy sentinel never matches runtime context. New writes always supply exact identity.
        try await database.schema(SkillAssignment.schema)
            .field("target_type", .string, .required, .sql(.default("legacy_unscoped")))
            .update()
        try await database.schema(SkillAssignment.schema)
            .field("target_id", .string, .required, .sql(.default("legacy_unscoped")))
            .update()
        if let sql = database as? any SQLDatabase {
            try await sql.raw(
                """
                CREATE UNIQUE INDEX IF NOT EXISTS uq_skill_assignments_target
                ON skill_assignments(project_id, skill_id, scope, target_type, target_id)
                """
            ).run()
        }
        try await database.schema(SkillPackageFile.schema)
            .id()
            .field("skill_package_id", .uuid, .required, .references(SkillPackage.schema, "id", onDelete: .cascade))
            .field("path", .string, .required)
            .field("content", .data, .required)
            .field("content_type", .string)
            .field("byte_count", .int, .required)
            .field("checksum", .string, .required)
            .field("created_at", .datetime)
            .unique(on: "skill_package_id", "path")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(SkillPackageFile.schema).delete()
        if let sql = database as? any SQLDatabase {
            try await sql.raw("DROP INDEX IF EXISTS uq_skill_assignments_target").run()
            try await sql.raw("DROP INDEX IF EXISTS uq_skill_overrides_repository").run()
            try await sql.raw("DROP INDEX IF EXISTS uq_skill_overrides_project_fallback").run()
        }
        try await database.schema(SkillAssignment.schema)
            .deleteField("target_type")
            .deleteField("target_id")
            .update()
        try await database.schema(SkillRuntimeOverride.schema)
            .deleteField("base_checksum")
            .deleteField("is_stale")
            .update()
        try await database.schema(CompiledSkill.schema)
            .deleteField("source_policy_json")
            .deleteField("source_policy_base_checksum")
            .deleteField("source_policy_stale")
            .update()
    }
}
