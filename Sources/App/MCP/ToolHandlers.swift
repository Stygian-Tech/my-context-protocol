import Fluent
import Vapor

struct ToolHandlers {
    static func handle(name: String, arguments: [String: String], db: Database, projectId: UUID) async throws -> String {
        if name.hasPrefix("skill:") {
            return try await handleSkillTool(name: name, arguments: arguments, db: db, projectId: projectId)
        }
        throw ToolHandlerError.unknownTool(name: name)
    }

    private static func handleSkillTool(name: String, arguments: [String: String], db: Database, projectId: UUID) async throws -> String {
        let project = try await Project.find(projectId, on: db)
        guard let releaseId = project?.activeReleaseId else {
            return "No active release"
        }

        let compiledIds = try await CompiledSkill.query(on: db)
            .filter(\.$release.$id == releaseId)
            .filter(\.$status == "ready")
            .all()
            .compactMap(\.id)

        guard !compiledIds.isEmpty else {
            return "No active release"
        }

        guard let cap = try await CapabilityDef.query(on: db)
            .filter(\.$compiledSkill.$id ~~ compiledIds)
            .filter(\.$capabilityName == name)
            .with(\.$compiledSkill)
            .first() else {
            return "Skill not found: \(name)"
        }

        let compiled = cap.compiledSkill
        return """
        Skill: \(compiled.name)
        Path: \(compiled.path)
        Summary: \(compiled.summary ?? "N/A")
        """
    }
}

enum ToolHandlerError: Error {
    case unknownTool(name: String)
}
