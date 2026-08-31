import Fluent
import Foundation
import Vapor

enum SkillRuntimeToolHandlers {
    private struct CanonicalSkillResponse: Codable {
        var schemaVersion = 1
        let kind: String
        let id: String
        let name: String
        let description: String
        let instructions: String
        let version: String
        let checksum: String
        let mediaType: String
        let resourceUri: String
        let source: SkillSource
        let files: [SkillPackageFileDescriptor]
    }

    private struct SkillFileResponse: Codable {
        var schemaVersion = 1
        let kind: String
        let id: String
        let version: String
        let path: String
        let checksum: String
        let mediaType: String
        let byteCount: Int
        let resourceUri: String
        let text: String?
        let blob: String?
        let encoding: String
        let source: SkillSource
    }

    static func handle(
        name: String,
        arguments: [String: JSONValue],
        db: Database,
        projectId: UUID
    ) async throws -> ToolHandlerOutput {
        switch name {
        case MCPConstants.resolveContextToolName: return try await resolve(arguments, db: db, projectId: projectId)
        case MCPConstants.getSkillToolName: return try await getSkill(arguments, db: db, projectId: projectId)
        case MCPConstants.reportSkillFeedbackToolName: return try await reportFeedback(arguments, db: db, projectId: projectId)
        case MCPConstants.catalogToolName: return try await legacyCatalog(arguments, db: db, projectId: projectId)
        case "discover_skills": return try await legacyDiscover(arguments, db: db, projectId: projectId)
        case "list_capabilities": return try await legacyListCapabilities(arguments, db: db, projectId: projectId)
        default: throw ToolHandlerError.unknownTool(name: name)
        }
    }

    private static func resolve(
        _ arguments: [String: JSONValue],
        db: Database,
        projectId: UUID
    ) async throws -> ToolHandlerOutput {
        guard let request = nonempty(string(arguments["request"])) else {
            throw Abort(.badRequest, reason: "request is required")
        }
        let contextArgument = arguments["context"]
        guard contextArgument == nil || decode(RuntimeContext.self, contextArgument) != nil else {
            throw Abort(.badRequest, reason: "context must be an object with string identity fields")
        }
        let currentSkillArgument = arguments["current_skill_ids"]
        guard currentSkillArgument == nil || decode([String].self, currentSkillArgument) != nil else {
            throw Abort(.badRequest, reason: "current_skill_ids must be an array of strings")
        }
        let toolsArgument = arguments["available_tools"]
        guard toolsArgument == nil || decode([RuntimeToolInventoryItem].self, toolsArgument) != nil else {
            throw Abort(.badRequest, reason: "available_tools must be an array of structured tool descriptions")
        }
        let event = try optionalBoundedString(arguments["event"], field: "event", max: 128)
        var context = decode(RuntimeContext.self, contextArgument) ?? .init()
        context.user = nonempty(string(arguments["user"])) ?? context.user
        context.organization = nonempty(string(arguments["organization"])) ?? context.organization
        context.workspace = nonempty(string(arguments["workspace"])) ?? context.workspace
        context.repository = nonempty(string(arguments["repository"])) ?? context.repository
        let response = try await SkillRuntimeResolver.resolve(
            projectId: projectId,
            request: request,
            event: event,
            context: context,
            currentSkillIds: decode([String].self, currentSkillArgument) ?? [],
            tools: decode([RuntimeToolInventoryItem].self, toolsArgument) ?? [],
            db: db
        )
        return output(response)
    }

    private static func legacyDiscover(
        _ arguments: [String: JSONValue],
        db: Database,
        projectId: UUID
    ) async throws -> ToolHandlerOutput {
        var normalized = arguments
        normalized["request"] = .string(
            nonempty(string(arguments["query"]))
                ?? "Discover the project skills relevant to the current task"
        )
        return try await resolve(normalized, db: db, projectId: projectId)
    }

    private static func getSkill(
        _ arguments: [String: JSONValue],
        db: Database,
        projectId: UUID
    ) async throws -> ToolHandlerOutput {
        guard let skillId = boundedString(arguments["skill_id"], field: "skill_id", max: 128) else {
            throw Abort(.badRequest, reason: "skill_id is required")
        }
        let version = try optionalBoundedString(arguments["version"], field: "version", max: 512)
        let (row, document) = try await SkillPackageResourceService.activeCompiledSkill(
            projectId: projectId, skillId: skillId, version: version, db: db
        )
        if let rawPath = try optionalBoundedString(arguments["path"], field: "path", max: 1_024) {
            let path = try SkillPackageResourceService.normalize(relativePath: rawPath)
            let file = try await SkillPackageResourceService.file(compiled: row, path: path, db: db)
            let resourceUri = SkillPackageResourceService.uri(
                skillId: skillId,
                path: path,
                version: document.version
            )
            let text = String(data: file.content, encoding: .utf8)
            let response = SkillFileResponse(
                kind: "file", id: skillId, version: document.version, path: path,
                checksum: file.checksum, mediaType: file.contentType ?? "application/octet-stream",
                byteCount: file.byteCount, resourceUri: resourceUri, text: text,
                blob: text == nil ? file.content.base64EncodedString() : nil,
                encoding: text == nil ? "base64" : "utf-8", source: document.source
            )
            let link = MCPToolContent.resourceLink(MCPToolResourceLink(
                uri: resourceUri, name: path, title: path,
                description: "Package file for \(skillId)@\(document.version)",
                mimeType: file.contentType ?? "application/octet-stream", size: file.byteCount
            ))
            return output(response, additionalContent: [link])
        }
        let files = try await SkillPackageResourceService.files(
            for: row,
            skillId: skillId,
            version: document.version,
            db: db
        )
        let response = CanonicalSkillResponse(
            kind: "skill", id: document.id, name: document.name, description: document.description,
            instructions: document.instructions, version: document.version, checksum: document.source.checksum,
            mediaType: "text/markdown",
            resourceUri: SkillPackageResourceService.uri(skillId: skillId, version: document.version),
            source: document.source, files: files
        )
        let links = files.map { file in
            MCPToolContent.resourceLink(MCPToolResourceLink(
                uri: file.resourceUri, name: file.path, title: file.path,
                description: "Package file for \(skillId)@\(document.version)",
                mimeType: file.mediaType, size: file.byteCount
            ))
        }
        return output(response, additionalContent: links)
    }

    private static func legacyListCapabilities(
        _ arguments: [String: JSONValue],
        db: Database,
        projectId: UUID
    ) async throws -> ToolHandlerOutput {
        let skillId = nonempty(string(arguments["skill_id"]))
        var normalized = arguments
        normalized["request"] = .string(skillId ?? "List available skill capabilities")
        if let skillId {
            normalized["current_skill_ids"] = .array([.string(skillId)])
        }
        let resolved = try await resolve(normalized, db: db, projectId: projectId)
        guard case .object(let response) = resolved.structuredContent else { return resolved }
        let bindings = response["capabilityBindings"] ?? .array([])
        var capabilities: Set<String> = []
        if case .array(let values) = bindings {
            for value in values {
                if case .object(let binding) = value,
                   case .string(let capability)? = binding["capability"] {
                    capabilities.insert(capability)
                }
            }
        }
        let legacy = JSONValue.object([
            "schemaVersion": .integer(1),
            "knownCapabilities": .array(capabilities.sorted().map(JSONValue.string)),
            "bindings": bindings,
            "unresolvedRequirements": response["missingRequirements"] ?? .array([]),
        ])
        return ToolHandlerOutput(text: SkillRuntimeJSON.encode(legacy), structuredContent: legacy)
    }

    private static func legacyCatalog(
        _ arguments: [String: JSONValue],
        db: Database,
        projectId: UUID
    ) async throws -> ToolHandlerOutput {
        let mode = nonempty(string(arguments["mode"]))?.lowercased()
        if mode == "skill" || nonempty(string(arguments["skill"])) != nil {
            var normalized = arguments
            normalized["skill_id"] = .string(normalizedSkillId(string(arguments["skill"]) ?? ""))
            let skill = try await getSkill(normalized, db: db, projectId: projectId)
            guard case .object(let document) = skill.structuredContent else { return skill }
            let name = document["name"]?.stringValue ?? document["id"]?.stringValue ?? "Skill"
            let instructions = document["instructions"]?.stringValue ?? skill.text
            return ToolHandlerOutput(
                text: "# \(name)\n\n\(instructions)",
                structuredContent: skill.structuredContent
            )
        }

        var normalized = arguments
        let request = nonempty(string(arguments["task"])) ?? "List the project skills relevant to the current task"
        normalized["request"] = .string(request)
        let resolved = try await resolve(normalized, db: db, projectId: projectId)
        let limited = mode == "route" || nonempty(string(arguments["task"])) != nil
            ? legacyLimitedResolution(resolved, rawLimit: arguments["limit"])
            : resolved
        let title = mode == "route" || nonempty(string(arguments["task"])) != nil
            ? "# MCP catalog route"
            : "# MCP catalog"
        return ToolHandlerOutput(
            text: "\(title)\n\nResolved by `resolve_context`.\n\n```json\n\(limited.text)\n```",
            structuredContent: limited.structuredContent
        )
    }

    private static func reportFeedback(
        _ arguments: [String: JSONValue],
        db: Database,
        projectId: UUID
    ) async throws -> ToolHandlerOutput {
        struct PersistedFeedback: Sendable {
            let id: UUID
            let draft: [String: String]
            let issueCreationEnabled: Bool
        }
        let categories = Set(["missing_guidance", "ambiguous_instruction", "incorrect_instruction", "conflict", "missing_capability", "poor_discovery", "outdated_content", "other"])
        guard let skillId = boundedString(arguments["skill_id"], field: "skill_id", max: 128),
              let version = boundedString(arguments["version"], field: "version", max: 512),
              let category = boundedString(arguments["category"], field: "category", max: 64), categories.contains(category),
              let summary = boundedString(arguments["summary"], field: "summary", max: 2_000),
              let evidence = boundedString(arguments["evidence"], field: "evidence", max: 8_000) else {
            throw Abort(.badRequest, reason: "skill_id, version, valid category, summary, and evidence are required strings within their limits")
        }
        let suggestedChange = try optionalBoundedString(arguments["suggested_change"], field: "suggested_change", max: 8_000)
        let persisted = try await db.transaction { transaction -> PersistedFeedback in
            guard let releaseId = try await MCPCatalogService.activeReleaseId(projectId: projectId, db: transaction),
                  let row = try await CompiledSkill.query(on: transaction).filter(\.$release.$id == releaseId)
                    .filter(\.$skillId == skillId).filter(\.$version == version).first(),
                  let document = SkillRuntimeJSON.decode(CompiledSkillDocument.self, from: row.canonicalJson) else {
                throw Abort(.notFound, reason: "The observed skill version is not active in this project")
            }
            let settings = try await ProjectRuntimeSettings.query(on: transaction)
                .filter(\.$project.$id == projectId)
                .first()
            let draft: [String: String] = [
                "title": "[Skill feedback] \(skillId): \(summary)",
                "body": "Skill: \(skillId)@\(version)\nSource: \(document.source.path)\nCategory: \(category)\n\nSummary: \(summary)\n\nEvidence: \(evidence)\n\nSuggested change: \(suggestedChange ?? "Not supplied")"
            ]
            let record = SkillFeedbackRecord(); record.$project.id = projectId; record.skillId = skillId
            record.skillVersion = version; record.sourcePath = document.source.path; record.sourceRevision = document.source.revision
            record.category = category; record.summary = summary; record.evidence = evidence
            record.suggestedChange = suggestedChange; record.issueDraftJson = SkillRuntimeJSON.encode(draft)
            try await record.save(on: transaction)
            guard let feedbackId = record.id else { throw Abort(.internalServerError, reason: "Feedback record has no id") }
            return PersistedFeedback(
                id: feedbackId,
                draft: draft,
                issueCreationEnabled: settings?.feedbackIssueCreationEnabled == true
            )
        }
        let requested = bool(arguments["create_issue"]) ?? false
        struct FeedbackResponse: Codable { var schemaVersion = 1; var feedbackId: UUID; var effectStatus: String; var issueDraft: [String: String]; var creationAuthorized: Bool; var message: String }
        return output(FeedbackResponse(
            feedbackId: persisted.id, effectStatus: "draft", issueDraft: persisted.draft,
            creationAuthorized: requested && persisted.issueCreationEnabled,
            message: requested && persisted.issueCreationEnabled
                ? "Issue creation is authorized, but the harness must execute the returned draft through its bound issue.create tool."
                : "Feedback was stored and no external side effect occurred."
        ))
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }; let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedSkillId(_ raw: String) -> String {
        let prefix = "ctx://skill/"
        let value = raw.hasPrefix(prefix) ? String(raw.dropFirst(prefix.count)) : raw
        return value.removingPercentEncoding ?? value
    }

    private static func string(_ value: JSONValue?) -> String? {
        value?.stringValue
    }

    private static func boundedString(_ value: JSONValue?, field: String, max: Int) -> String? {
        guard case .string(let raw) = value else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= max else { return nil }
        return trimmed
    }

    private static func optionalBoundedString(_ value: JSONValue?, field: String, max: Int) throws -> String? {
        guard let value else { return nil }
        guard let result = boundedString(value, field: field, max: max) else {
            throw Abort(.badRequest, reason: "\(field) must be a nonempty string no longer than \(max) characters")
        }
        return result
    }

    private static func bool(_ value: JSONValue?) -> Bool? {
        switch value {
        case .bool(let value): return value
        case .string(let value): return Bool(value)
        default: return nil
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ value: JSONValue?) -> T? {
        guard let value else { return nil }
        if case .string(let legacyJSON) = value {
            return SkillRuntimeJSON.decode(type, from: legacyJSON)
        }
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func legacyLimitedResolution(
        _ output: ToolHandlerOutput,
        rawLimit: JSONValue?
    ) -> ToolHandlerOutput {
        let raw: Int?
        switch rawLimit {
        case .integer(let value): raw = value
        case .string(let value): raw = Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default: raw = nil
        }
        let limit = min(max(raw ?? 5, 1), 20)
        guard case .object(var response) = output.structuredContent else { return output }
        var remaining = limit
        var selectedSkillIds = Set<String>()
        for key in ["activeSkills", "suggestedTaskSkills"] {
            guard case .array(let values) = response[key] else { continue }
            let selected = Array(values.prefix(remaining))
            response[key] = .array(selected)
            for value in selected {
                if case .object(let skill) = value, case .string(let id)? = skill["id"] {
                    selectedSkillIds.insert(id)
                }
            }
            remaining -= selected.count
        }
        if case .array(let actions) = response["nextActions"] {
            response["nextActions"] = .array(actions.filter { value in
                guard case .object(let action) = value,
                      case .string(let skillId)? = action["skillId"] else { return true }
                return selectedSkillIds.contains(skillId)
            })
        }
        let structured = JSONValue.object(response)
        return ToolHandlerOutput(text: SkillRuntimeJSON.encode(structured), structuredContent: structured)
    }

    private static func output<T: Encodable>(_ value: T, additionalContent: [MCPToolContent] = []) -> ToolHandlerOutput {
        let text = SkillRuntimeJSON.encode(value)
        let structured = SkillRuntimeJSON.decode(JSONValue.self, from: text)
        return ToolHandlerOutput(text: text, structuredContent: structured, additionalContent: additionalContent)
    }
}
