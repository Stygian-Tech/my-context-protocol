import Fluent
import SQLKit

struct AddSkillUsageAnalytics: AsyncMigration {
    func prepare(on db: Database) async throws {
        // Separate alterations remain compatible with SQLite.
        try await db.schema(SkillRuntimeEvent.schema).field("release_id", .uuid).update()
        for field in ["skill_version", "source_checksum", "client_identity", "source"] {
            try await db.schema(SkillRuntimeEvent.schema).field(FieldKey(stringLiteral: field), .string).update()
        }
        try await db.schema(SkillUsageReport.schema).id()
            .field("project_id", .uuid, .required, .references(Project.schema, "id", onDelete: .cascade))
            .field("client_identity", .string, .required).field("report_id", .string, .required)
            .field("payload_hash", .string, .required).field("recorded_count", .int, .required)
            .field("created_at", .datetime)
            .unique(on: "project_id", "client_identity", "report_id").create()
        if let sql = db as? any SQLDatabase {
            try await sql.raw("CREATE INDEX skill_usage_project_time ON skill_runtime_events (project_id, created_at, skill_id)").run()
            try await sql.raw("CREATE INDEX skill_usage_trace_client ON skill_runtime_events (project_id, trace_id, client_identity)").run()
        }
    }
    func revert(on db: Database) async throws {
        if let sql = db as? any SQLDatabase {
            try await sql.raw("DROP INDEX IF EXISTS skill_usage_project_time").run()
            try await sql.raw("DROP INDEX IF EXISTS skill_usage_trace_client").run()
        }
        try await db.schema(SkillUsageReport.schema).delete()
        for field in ["release_id", "skill_version", "source_checksum", "client_identity", "source"] {
            try await db.schema(SkillRuntimeEvent.schema).deleteField(FieldKey(stringLiteral: field)).update()
        }
    }
}
