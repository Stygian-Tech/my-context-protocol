import Fluent
import Foundation
import Vapor

enum SkillRuntimeToolHandlers {
    static func handle(name: String, arguments: [String: String], db: Database, projectId: UUID) async throws -> String {
        switch name {
        case "resolve_context": return try await resolve(arguments, db: db, projectId: projectId)
        case "discover_skills": return try await discover(arguments, db: db, projectId: projectId)
        case "get_skill": return try await getSkill(arguments, db: db, projectId: projectId)
        case "list_capabilities": return try await listCapabilities(arguments, db: db, projectId: projectId)
        case "report_skill_feedback": return try await reportFeedback(arguments, db: db, projectId: projectId)
        default: throw ToolHandlerError.unknownTool(name: name)
        }
    }

    private static func resolve(_ arguments: [String: String], db: Database, projectId: UUID) async throws -> String {
        guard let request = nonempty(arguments["request"]) else { throw Abort(.badRequest, reason: "request is required") }
        let context = RuntimeContext(
            user: nonempty(arguments["user"]), organization: nonempty(arguments["organization"]),
            workspace: nonempty(arguments["workspace"]), repository: nonempty(arguments["repository"])
        )
        let response = try await SkillRuntimeResolver.resolve(
            projectId: projectId, request: request, context: context,
            tools: decode([RuntimeToolInventoryItem].self, arguments["available_tools"]) ?? [], db: db
        )
        return SkillRuntimeJSON.encode(response)
    }

    private static func discover(_ arguments: [String: String], db: Database, projectId: UUID) async throws -> String {
        let query = nonempty(arguments["query"]) ?? ""
        let response = try await SkillRuntimeResolver.resolve(
            projectId: projectId, request: query, event: nonempty(arguments["event"]),
            context: decode(RuntimeContext.self, arguments["context"]) ?? .init(),
            currentSkillIds: decode([String].self, arguments["current_skill_ids"]) ?? [],
            tools: decode([RuntimeToolInventoryItem].self, arguments["available_tools"]) ?? [], db: db
        )
        return SkillRuntimeJSON.encode(response)
    }

    private static func getSkill(_ arguments: [String: String], db: Database, projectId: UUID) async throws -> String {
        guard let skillId = nonempty(arguments["skill_id"]),
              let releaseId = try await MCPCatalogService.activeReleaseId(projectId: projectId, db: db) else {
            throw Abort(.badRequest, reason: "skill_id is required and the project must have an active release")
        }
        var query = CompiledSkill.query(on: db).filter(\.$release.$id == releaseId).filter(\.$skillId == skillId)
        if let version = nonempty(arguments["version"]) { query = query.filter(\.$version == version) }
        guard let row = try await query.first(),
              let document = SkillRuntimeJSON.decode(CompiledSkillDocument.self, from: row.canonicalJson) else {
            throw Abort(.notFound, reason: "Compiled skill not found")
        }
        return SkillRuntimeJSON.encode(document)
    }

    private static func listCapabilities(_ arguments: [String: String], db: Database, projectId: UUID) async throws -> String {
        let tools = decode([RuntimeToolInventoryItem].self, arguments["available_tools"]) ?? []
        let skillId = nonempty(arguments["skill_id"])
        let response = try await SkillRuntimeResolver.resolve(
            projectId: projectId, request: skillId ?? "", currentSkillIds: skillId.map { [$0] } ?? [], tools: tools, db: db
        )
        struct Payload: Codable { var schemaVersion = 1; var knownCapabilities: [String]; var bindings: [CapabilityBindingResult]; var unresolvedRequirements: [String] }
        return SkillRuntimeJSON.encode(Payload(
            knownCapabilities: Array(Set(response.capabilityBindings.map(\.capability))).sorted(),
            bindings: response.capabilityBindings, unresolvedRequirements: response.missingRequirements
        ))
    }

    private static func reportFeedback(_ arguments: [String: String], db: Database, projectId: UUID) async throws -> String {
        let categories = Set(["missing_guidance", "ambiguous_instruction", "incorrect_instruction", "conflict", "missing_capability", "poor_discovery", "outdated_content", "other"])
        guard let skillId = nonempty(arguments["skill_id"]), let version = nonempty(arguments["version"]),
              let category = nonempty(arguments["category"]), categories.contains(category),
              let summary = nonempty(arguments["summary"]) else { throw Abort(.badRequest, reason: "skill_id, version, valid category, and summary are required") }
        guard let releaseId = try await MCPCatalogService.activeReleaseId(projectId: projectId, db: db),
              let row = try await CompiledSkill.query(on: db).filter(\.$release.$id == releaseId)
                .filter(\.$skillId == skillId).filter(\.$version == version).first(),
              let document = SkillRuntimeJSON.decode(CompiledSkillDocument.self, from: row.canonicalJson) else {
            throw Abort(.notFound, reason: "The observed skill version is not active in this project")
        }
        let draft: [String: String] = [
            "title": "[Skill feedback] \(skillId): \(summary)",
            "body": "Skill: \(skillId)@\(version)\nSource: \(document.source.path)\nCategory: \(category)\n\nSummary: \(summary)\n\nEvidence: \(nonempty(arguments["evidence"]) ?? "Not supplied")\n\nSuggested change: \(nonempty(arguments["suggested_change"]) ?? "Not supplied")"
        ]
        let record = SkillFeedbackRecord(); record.$project.id = projectId; record.skillId = skillId
        record.skillVersion = version; record.sourcePath = document.source.path; record.sourceRevision = document.source.revision
        record.category = category; record.summary = summary; record.evidence = nonempty(arguments["evidence"])
        record.suggestedChange = nonempty(arguments["suggested_change"]); record.issueDraftJson = SkillRuntimeJSON.encode(draft)
        try await record.save(on: db)
        let settings = try await ProjectRuntimeSettings.query(on: db).filter(\.$project.$id == projectId).first()
        let requested = nonempty(arguments["create_issue"])?.lowercased() == "true"
        struct FeedbackResponse: Codable { var schemaVersion = 1; var feedbackId: UUID; var effectStatus: String; var issueDraft: [String: String]; var creationAuthorized: Bool; var message: String }
        return SkillRuntimeJSON.encode(FeedbackResponse(
            feedbackId: record.id!, effectStatus: "draft", issueDraft: draft,
            creationAuthorized: requested && settings?.feedbackIssueCreationEnabled == true,
            message: requested && settings?.feedbackIssueCreationEnabled == true
                ? "Issue creation is authorized, but the harness must execute the returned draft through its bound issue.create tool."
                : "Feedback was stored and no external side effect occurred."
        ))
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }; let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    private static func decode<T: Decodable>(_ type: T.Type, _ value: String?) -> T? { SkillRuntimeJSON.decode(type, from: value) }
}
