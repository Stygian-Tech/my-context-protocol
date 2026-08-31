import Fluent
import Foundation
import Vapor

struct ToolHandlerOutput {
    let text: String
    let structuredContent: JSONValue?
    let content: [MCPToolContent]

    init(text: String, structuredContent: JSONValue?, additionalContent: [MCPToolContent] = []) {
        self.text = text
        self.structuredContent = structuredContent
        self.content = [.text(ToolContentItem(text: text))] + additionalContent
    }

    static func text(_ text: String) -> ToolHandlerOutput {
        ToolHandlerOutput(text: text, structuredContent: nil)
    }
}

struct ToolHandlers {
    static func handle(
        name: String,
        arguments: [String: JSONValue],
        db: Database,
        projectId: UUID
    ) async throws -> ToolHandlerOutput {
        if MCPConstants.callableRuntimeToolNames.contains(name) {
            return try await SkillRuntimeToolHandlers.handle(name: name, arguments: arguments, db: db, projectId: projectId)
        }
        // Legacy colon-prefixed names are no longer accepted on the wire.
        if name.contains(":") {
            throw ToolHandlerError.unknownTool(name: name)
        }
        guard try await legacyCompiledToolsEnabled(db: db, projectId: projectId) else {
            throw ToolHandlerError.unknownTool(name: name)
        }
        return try await handleCompiledTool(name: name, arguments: arguments, db: db, projectId: projectId)
    }

    static func legacyCompiledToolsEnabled(db: Database, projectId: UUID) async throws -> Bool {
        guard let settings = try await ProjectRuntimeSettings.query(on: db)
            .filter(\.$project.$id == projectId)
            .first(),
              let raw = settings.providerPreferencesJson,
              let data = raw.data(using: .utf8),
              let preferences = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return preferences[MCPConstants.legacyCompiledToolsPreferenceKey] as? Bool == true
    }

    private static func handleCompiledTool(
        name: String,
        arguments: [String: JSONValue],
        db: Database,
        projectId: UUID
    ) async throws -> ToolHandlerOutput {
        let project = try await Project.find(projectId, on: db)
        guard let releaseId = project?.activeReleaseId else {
            return .text("No active release")
        }

        let compiledIds = try await CompiledSkill.query(on: db)
            .filter(\.$release.$id == releaseId)
            .filter(\.$status == "ready")
            .all()
            .compactMap(\.id)

        guard !compiledIds.isEmpty else {
            return .text("No active release")
        }

        guard let cap = try await CapabilityDef.query(on: db)
            .filter(\.$compiledSkill.$id ~~ compiledIds)
            .filter(\.$capabilityName == name)
            .filter(\.$type == "tool")
            .with(\.$compiledSkill)
            .first() else {
            return .text("Skill not found: \(name)")
        }

        let compiled = cap.compiledSkill
        let detailRaw = arguments["detail"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
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
        return .text(lines.joined(separator: "\n"))
    }

}

enum ToolHandlerError: Error {
    case unknownTool(name: String)
}
