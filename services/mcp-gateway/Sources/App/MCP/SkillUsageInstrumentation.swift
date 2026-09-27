import Fluent
import Foundation

/// Shared entry point for successful MCP delivery observations. No request content is retained.
enum SkillUsageInstrumentation {
    static func collectionEnabled(projectId: UUID, db: Database) async -> Bool {
        do {
            return try await ProjectRuntimeSettings.query(on: db)
                .filter(\.$project.$id == projectId).first()?.telemetryEnabled == true
        } catch {
            db.logger.warning("Unable to read skill usage collection settings")
            return false
        }
    }

    static func surfaced(_ skills: [CompiledSkill], projectId: UUID, clientIdentity: String, source: String, db: Database) async {
        var seen = Set<UUID>()
        let observations = skills.compactMap { skill -> SkillUsageObservation? in
            guard let id = skill.id, seen.insert(id).inserted else { return nil }
            return .init(skill: skill, measurement: .surfaced, source: source)
        }
        await SkillUsageService.record(projectId: projectId, clientIdentity: clientIdentity, events: observations, db: db, logger: db.logger)
    }

    static func delivered(_ skill: CompiledSkill, path: String? = nil, projectId: UUID, clientIdentity: String, source: String, db: Database) async {
        // SKILL.md itself contains the instructions; other package files are supporting reads.
        let measurement: SkillUsageMeasurement = path == nil || path == "SKILL.md" ? .instructionsDelivered : .supportingFileRead
        await SkillUsageService.record(projectId: projectId, clientIdentity: clientIdentity,
            events: [.init(skill: skill, measurement: measurement, source: source)], db: db, logger: db.logger)
    }
}
