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

        let skillName = String(name.dropFirst("skill:".count))
        let skillPackage = try await SkillPackage.query(on: db)
            .filter(\.$release.$id == releaseId)
            .filter(\.$name == skillName)
            .first()

        guard let skill = skillPackage else {
            return "Skill not found: \(skillName)"
        }

        return """
        Skill: \(skill.name)
        Path: \(skill.path)
        Description: \(skill.description ?? "N/A")
        """
    }
}

enum ToolHandlerError: Error {
    case unknownTool(name: String)
}
