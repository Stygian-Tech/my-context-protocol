import Fluent
import Foundation
import SQLKit
import Vapor

enum MCPCatalogService {
    static func activeReleaseId(projectId: UUID, db: Database) async throws -> UUID? {
        try await Project.find(projectId, on: db)?.activeReleaseId
    }

    /// Fetches only the `id` column for ready compiled skills — avoids transferring `skill_body`,
    /// `body_diff_unified`, and other large text fields that are not needed for ID-based catalog lookups.
    static func readyCompiledSkillIds(releaseId: UUID, db: Database) async throws -> [UUID] {
        if let sql = db as? SQLDatabase {
            struct Row: Decodable { let id: UUID }
            let rows = try await sql.select()
                .column("id")
                .from(CompiledSkill.schema)
                .where(SQLColumn("release_id"), .equal, SQLBind(releaseId))
                .where(SQLColumn("status"), .equal, SQLBind("ready"))
                .all(decoding: Row.self)
            return rows.map(\.id)
        }
        // Fallback for non-SQL backends (e.g. in-memory test doubles).
        return try await CompiledSkill.query(on: db)
            .filter(\.$release.$id == releaseId)
            .filter(\.$status == "ready")
            .all()
            .compactMap(\.id)
    }

    static func capabilityDefs(
        compiledSkillIds: [UUID],
        types: [String],
        db: Database
    ) async throws -> [CapabilityDef] {
        guard !compiledSkillIds.isEmpty, !types.isEmpty else { return [] }
        return try await CapabilityDef.query(on: db)
            .filter(\.$compiledSkill.$id ~~ compiledSkillIds)
            .filter(\.$type ~~ types)
            .with(\.$compiledSkill) { skill in
                skill.with(\.$routingRules)
            }
            .all()
    }
}
