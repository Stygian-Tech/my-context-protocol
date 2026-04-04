import Fluent
import Foundation
import Vapor

enum MCPCatalogService {
    static func activeReleaseId(projectId: UUID, db: Database) async throws -> UUID? {
        try await Project.find(projectId, on: db)?.activeReleaseId
    }

    static func readyCompiledSkillIds(releaseId: UUID, db: Database) async throws -> [UUID] {
        try await CompiledSkill.query(on: db)
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
