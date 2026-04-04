import Fluent
import Vapor

struct ToolHandlers {
    static func handle(name: String, arguments: [String: String], db: Database, projectId: UUID) async throws -> String {
        if name == MCPConstants.catalogToolName {
            return try await McpCatalogMarkdown.build(db: db, projectId: projectId)
        }
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
        let detailRaw = arguments["detail"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = (detailRaw?.isEmpty == false) ? detailRaw : nil
        var lines = [
            "Skill: \(compiled.name)",
            "Path: \(compiled.path)",
            "Summary: \(compiled.summary ?? "N/A")"
        ]
        if let detail {
            lines.append("Detail: \(detail)")
        }
        if let body = compiled.skillBody?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
            lines.append("")
            lines.append("---")
            lines.append(body)
        }
        return lines.joined(separator: "\n")
    }
}

enum ToolHandlerError: Error {
    case unknownTool(name: String)
}
