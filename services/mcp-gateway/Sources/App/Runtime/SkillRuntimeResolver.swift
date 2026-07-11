import Crypto
import Fluent
import Foundation

struct RuntimeToolInventoryItem: Codable, Sendable {
    var server: String
    var name: String
    var description: String?
    var inputSchema: String?
    var provider: String?
}

struct RuntimeContext: Codable, Sendable {
    var user: String? = nil
    var organization: String? = nil
    var workspace: String? = nil
    var repository: String? = nil
}

struct CapabilityBindingResult: Codable, Sendable {
    var capability: String
    var required: Bool
    var selectedServer: String?
    var selectedTool: String?
    var confidence: Double
    var alternatives: [String]
    var missing: Bool
    var fallback: String
    var reason: String
}

struct ResolvedSkillResult: Codable, Sendable {
    var id: String
    var version: String
    var kind: String
    var scope: String
    var enforcement: String
    var priority: Int
    var selectionReason: String
    var score: Double
    var instructions: String?
    var contentIncluded: Bool
    var resourceUri: String
    var source: SkillSource
}

struct ResolutionConflict: Codable, Sendable { var skillId: String; var conflictsWith: String; var unresolved: Bool }
struct ResolutionTraceStep: Codable, Sendable { var skillId: String?; var outcome: String; var reason: String; var score: Double? }

struct SkillResolutionResponse: Codable, Sendable {
    var schemaVersion: Int = 1
    var traceId: UUID
    var activeSkills: [ResolvedSkillResult]
    var suggestedTaskSkills: [ResolvedSkillResult]
    var capabilityBindings: [CapabilityBindingResult]
    var missingRequirements: [String]
    var conflicts: [ResolutionConflict]
    var missingContext: [String]
    var eventCanonical: Bool?
    var resolutionTrace: [ResolutionTraceStep]
}

enum SkillRuntimeResolver {
    static let canonicalEvents: Set<String> = [
        "issue_discovered", "non_blocking_issue_discovered", "follow_up_work_identified",
        "blocker_encountered", "test_failed", "task_completed", "skill_inadequate",
        "skill_ambiguous", "instruction_conflict_detected", "security_concern_detected"
    ]
    static let inlineLimit = 65_536

    static func resolve(
        projectId: UUID,
        request: String,
        event: String? = nil,
        context: RuntimeContext = .init(),
        currentSkillIds: [String] = [],
        tools: [RuntimeToolInventoryItem] = [],
        db: Database
    ) async throws -> SkillResolutionResponse {
        let traceId = UUID()
        guard let project = try await Project.find(projectId, on: db), let releaseId = project.activeReleaseId else {
            return .init(traceId: traceId, activeSkills: [], suggestedTaskSkills: [], capabilityBindings: [], missingRequirements: [], conflicts: [], missingContext: ["activeRelease"], eventCanonical: event.map(canonicalEvents.contains), resolutionTrace: [])
        }
        let rows = try await CompiledSkill.query(on: db)
            .filter(\.$release.$id == releaseId).filter(\.$status == "ready").all()
        let assignments = try await SkillAssignment.query(on: db).filter(\.$project.$id == projectId).all()
        let settings = try await ProjectRuntimeSettings.query(on: db).filter(\.$project.$id == projectId).first()
        let assignmentBySkill = Dictionary(grouping: assignments, by: \.skillId)
        let queryTokens = tokens(request + " " + (event ?? ""))
        var active: [(ResolvedSkillResult, CompiledSkillDocument)] = []
        var suggested: [(ResolvedSkillResult, CompiledSkillDocument)] = []
        var trace: [ResolutionTraceStep] = []

        for row in rows {
            guard let document = SkillRuntimeJSON.decode(CompiledSkillDocument.self, from: row.canonicalJson) else {
                trace.append(.init(skillId: row.skillId ?? row.name, outcome: "excluded", reason: "missing_canonical_document", score: nil))
                continue
            }
            let explicitAssignments = assignmentBySkill[document.id] ?? []
            let controllingAssignment = explicitAssignments.sorted { lhs, rhs in
                if lhs.required != rhs.required { return lhs.required }
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                return lhs.scope < rhs.scope
            }.first
            let isCurrent = currentSkillIds.contains(document.id)
            let assigned = !explicitAssignments.isEmpty
            let eventMatch = event.map { document.activation.events.contains($0) } ?? false
            let keywordScore = score(document: document, tokens: queryTokens)
            let semanticScore = if settings?.semanticEnabled == true {
                try await semanticScore(document: document, request: request, projectId: projectId, db: db)
            } else { 0.0 }
            let combinedScore = keywordScore + semanticScore
            let intentMatch = combinedScore > 0
            let always = document.activation.mode == .always
            let automaticEligible = !document.validation.clarificationRequired
            let selected = isCurrent || assigned || (automaticEligible && (always || eventMatch || intentMatch))
            guard selected else {
                trace.append(.init(skillId: document.id, outcome: "excluded", reason: document.validation.clarificationRequired ? "clarification_required" : "no_activation_match", score: combinedScore))
                continue
            }
            let reason = isCurrent ? "already_active" : assigned ? "explicit_assignment" : always ? "always_active" : eventMatch ? "event_match" : "intent_match"
            let instructions = document.instructions.utf8.count <= inlineLimit ? document.instructions : nil
            let result = ResolvedSkillResult(
                id: document.id, version: document.version, kind: document.kind.rawValue,
                scope: controllingAssignment?.scope ?? document.scope.rawValue,
                enforcement: controllingAssignment?.required == true ? SkillEnforcement.required.rawValue : document.enforcement.rawValue,
                priority: controllingAssignment?.priority ?? document.priority,
                selectionReason: reason, score: combinedScore, instructions: instructions,
                contentIncluded: instructions != nil,
                resourceUri: CapabilitySchemaBuilder.resourceURI(skillName: document.id), source: document.source
            )
            if isCurrent || assigned || always || (document.kind == .operating && document.enforcement == .required) {
                active.append((result, document))
            } else {
                suggested.append((result, document))
            }
            trace.append(.init(skillId: document.id, outcome: "selected", reason: reason, score: combinedScore))
        }

        active.sort { ordered($0.0, $1.0) }
        suggested.sort { ordered($0.0, $1.0) }
        let selected = active + suggested
        let bindings = selected.flatMap { pair in pair.1.requires.map { bind($0, tools: tools) } }
        let missing = bindings.filter(\.missing).map(\.capability)
        let selectedIds = Set(selected.map { $0.1.id })
        let conflicts = selected.flatMap { pair in
            pair.1.conflictsWith.filter(selectedIds.contains).map { ResolutionConflict(skillId: pair.1.id, conflictsWith: $0, unresolved: true) }
        }
        let missingContext = [
            context.organization == nil ? "organization" : nil,
            context.workspace == nil ? "workspace" : nil,
            context.repository == nil ? "repository" : nil
        ].compactMap { $0 }

        let response = SkillResolutionResponse(
            traceId: traceId, activeSkills: active.map(\.0), suggestedTaskSkills: suggested.map(\.0),
            capabilityBindings: bindings, missingRequirements: missing, conflicts: conflicts,
            missingContext: missingContext, eventCanonical: event.map(canonicalEvents.contains), resolutionTrace: trace
        )
        try await recordTelemetry(response, request: request, projectId: projectId, db: db)
        return response
    }

    private static func ordered(_ lhs: ResolvedSkillResult, _ rhs: ResolvedSkillResult) -> Bool {
        let scopeOrder = ["global": 0, "organization": 1, "workspace": 2, "repository": 3, "task": 4]
        if lhs.enforcement != rhs.enforcement { return lhs.enforcement == "required" }
        if (scopeOrder[lhs.scope] ?? 9) != (scopeOrder[rhs.scope] ?? 9) { return (scopeOrder[lhs.scope] ?? 9) < (scopeOrder[rhs.scope] ?? 9) }
        if lhs.selectionReason != rhs.selectionReason {
            let explicit = ["already_active", "explicit_assignment"]
            if explicit.contains(lhs.selectionReason) != explicit.contains(rhs.selectionReason) { return explicit.contains(lhs.selectionReason) }
        }
        if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        return lhs.id < rhs.id
    }

    private static func score(document: CompiledSkillDocument, tokens queryTokens: Set<String>) -> Double {
        guard !queryTokens.isEmpty else { return 0 }
        let fields: [(String, Double)] = [
            (document.id, 10), (document.description, 5),
            (document.activation.intents.joined(separator: " "), 7),
            (document.activation.tags.joined(separator: " "), 6),
            (document.activation.examples.joined(separator: " "), 4)
        ]
        return fields.reduce(0) { total, field in total + Double(tokens(field.0).intersection(queryTokens).count) * field.1 }
    }

    private static func tokens(_ value: String) -> Set<String> {
        Set(value.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 2 })
    }

    private static func semanticScore(document: CompiledSkillDocument, request: String, projectId: UUID, db: Database) async throws -> Double {
        let provider = "deterministic-fallback"
        let model = "token-buckets-v1"
        let searchable = [document.id, document.description, document.activation.intents.joined(separator: " "), document.activation.tags.joined(separator: " "), document.activation.examples.joined(separator: " ")].joined(separator: " ")
        let skillVector: [Double]
        if let record = try await SkillEmbeddingRecord.query(on: db)
            .filter(\.$project.$id == projectId).filter(\.$skillId == document.id)
            .filter(\.$sourceChecksum == document.source.checksum).filter(\.$provider == provider).filter(\.$model == model).first(),
           let stored = SkillRuntimeJSON.decode([Double].self, from: record.vectorJson) {
            skillVector = stored
        } else {
            skillVector = semanticVector(searchable)
            try await SkillEmbeddingRecord.query(on: db).filter(\.$project.$id == projectId).filter(\.$skillId == document.id)
                .filter(\.$provider == provider).filter(\.$model == model).delete()
            let record = SkillEmbeddingRecord(); record.$project.id = projectId; record.skillId = document.id
            record.sourceChecksum = document.source.checksum; record.provider = provider; record.model = model
            record.vectorJson = SkillRuntimeJSON.encode(skillVector); try await record.save(on: db)
        }
        return cosine(semanticVector(request), skillVector)
    }

    private static func semanticVector(_ text: String) -> [Double] {
        var vector = Array(repeating: 0.0, count: 64)
        for token in tokens(text) {
            let digest = SHA256.hash(data: Data(token.utf8))
            let index = digest.withUnsafeBytes { bytes in Int(bytes[0]) } % vector.count
            vector[index] += 1
        }
        let length = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        return length == 0 ? vector : vector.map { $0 / length }
    }

    private static func cosine(_ lhs: [Double], _ rhs: [Double]) -> Double {
        guard lhs.count == rhs.count else { return 0 }
        return zip(lhs, rhs).reduce(0) { $0 + $1.0 * $1.1 }
    }

    private static func bind(_ requirement: SkillRequirement, tools: [RuntimeToolInventoryItem]) -> CapabilityBindingResult {
        let parts = Set(requirement.capability.lowercased().split(separator: ".").map(String.init))
        var candidates: [(tool: RuntimeToolInventoryItem, score: Int)] = []
        for tool in tools {
            let combined = [tool.server, tool.name, tool.description ?? "", tool.provider ?? ""].joined(separator: " ")
            let matched = tokens(combined).intersection(parts).count
            if matched > 0 { candidates.append((tool: tool, score: matched)) }
        }
        let ranked = candidates.sorted { lhs, rhs in
            lhs.score == rhs.score ? lhs.tool.name < rhs.tool.name : lhs.score > rhs.score
        }
        let selected = ranked.first
        let confidence: Double
        if let selected { confidence = min(1, Double(selected.score) / Double(max(parts.count, 1))) } else { confidence = 0 }
        let alternatives = ranked.dropFirst().map { item in item.tool.server + "/" + item.tool.name }
        return .init(
            capability: requirement.capability, required: requirement.required,
            selectedServer: selected?.tool.server, selectedTool: selected?.tool.name,
            confidence: confidence, alternatives: alternatives, missing: selected == nil,
            fallback: requirement.onMissing.rawValue,
            reason: selected == nil ? "No available tool matched the abstract capability." : "Matched capability terms against server, tool, provider, and description metadata."
        )
    }

    private static func recordTelemetry(_ response: SkillResolutionResponse, request: String, projectId: UUID, db: Database) async throws {
        guard let settings = try await ProjectRuntimeSettings.query(on: db).filter(\.$project.$id == projectId).first(), settings.telemetryEnabled else { return }
        let cutoff = Date().addingTimeInterval(-Double(settings.telemetryRetentionDays) * 86_400)
        try await SkillRuntimeEvent.query(on: db).filter(\.$project.$id == projectId).filter(\.$createdAt < cutoff).delete()
        let hash = SHA256.hash(data: Data(request.utf8)).map { String(format: "%02x", $0) }.joined()
        for skill in response.activeSkills + response.suggestedTaskSkills {
            let event = SkillRuntimeEvent()
            event.$project.id = projectId; event.traceId = response.traceId; event.eventType = "skill_selected"
            event.skillId = skill.id; event.reasonCode = skill.selectionReason; event.score = skill.score
            event.requestHash = hash; event.detailJson = "{}"
            try await event.save(on: db)
        }
    }
}
