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
    var task: String? = nil
}

struct CapabilityBindingResult: Codable, Sendable {
    var skillId: String? = nil
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
struct ResolutionNextAction: Codable, Sendable {
    var order: Int
    var type: String
    var skillId: String?
    var capability: String?
    var instruction: String
    var resourceUri: String?
}

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
    var nextActions: [ResolutionNextAction]
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
            return .init(traceId: traceId, activeSkills: [], suggestedTaskSkills: [], capabilityBindings: [], missingRequirements: [], conflicts: [], missingContext: ["activeRelease"], eventCanonical: event.map(canonicalEvents.contains), nextActions: [], resolutionTrace: [])
        }
        let rows = try await CompiledSkill.query(on: db)
            .filter(\.$release.$id == releaseId).filter(\.$status == "ready").all()
        let assignments = try await SkillAssignment.query(on: db).filter(\.$project.$id == projectId).all()
        let assignmentBySkill = Dictionary(grouping: assignments, by: \.skillId)
        let queryTokens = tokens(request + " " + (event ?? ""))
        var active: [(ResolvedSkillResult, CompiledSkillDocument)] = []
        var suggested: [(ResolvedSkillResult, CompiledSkillDocument)] = []
        var bindings: [CapabilityBindingResult] = []
        var trace: [ResolutionTraceStep] = []

        for row in rows {
            guard let document = SkillRuntimeJSON.decode(CompiledSkillDocument.self, from: row.canonicalJson) else {
                trace.append(.init(skillId: row.skillId ?? row.name, outcome: "excluded", reason: "missing_canonical_document", score: nil))
                continue
            }
            let explicitAssignments = assignmentBySkill[document.id] ?? []
            let applicableAssignments = explicitAssignments.filter {
                assignmentApplies($0, projectId: projectId, context: context)
            }
            let controllingAssignment = applicableAssignments.sorted { lhs, rhs in
                if lhs.required != rhs.required { return lhs.required }
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                return lhs.scope < rhs.scope
            }.first
            let isCurrent = currentSkillIds.contains(document.id)
            let eventMatch = event.map { document.activation.events.contains($0) } ?? false
            let keywordScore = score(document: document, tokens: queryTokens)
            let combinedScore = keywordScore
            let intentMatch = combinedScore > 0
            let always = document.activation.mode == .always
            let documentActivated = activationMatches(
                document.activation.mode.rawValue,
                isCurrent: isCurrent,
                eventMatch: eventMatch,
                intentMatch: intentMatch
            )
            let assignmentActivated = controllingAssignment.map {
                activationMatches($0.activationMode, isCurrent: isCurrent, eventMatch: eventMatch, intentMatch: intentMatch)
            } ?? false
            let assigned = controllingAssignment != nil && assignmentActivated
            let documentContextApplies = scopeHasContext(document.scope, context: context)
            if !isCurrent, avoidMatch(document.avoidWhen ?? [], tokens: queryTokens) {
                trace.append(.init(skillId: document.id, outcome: "excluded", reason: "avoid_when_match", score: combinedScore))
                continue
            }
            let automaticEligible = !document.validation.clarificationRequired
            let selected = isCurrent || assigned || (automaticEligible && documentContextApplies && documentActivated)
            guard selected else {
                let reason = document.validation.clarificationRequired
                    ? "clarification_required"
                    : !documentContextApplies && documentActivated
                        ? "missing_scope_context"
                        : "no_activation_match"
                trace.append(.init(skillId: document.id, outcome: "excluded", reason: reason, score: combinedScore))
                continue
            }
            let documentBindings = document.requires.map { requirement in
                var binding = bind(requirement, tools: tools)
                binding.skillId = document.id
                return binding
            }
            bindings.append(contentsOf: documentBindings)
            if documentBindings.contains(where: { $0.required && $0.missing && $0.fallback == MissingCapabilityFallback.failActivation.rawValue }) {
                trace.append(.init(skillId: document.id, outcome: "excluded", reason: "required_capability_missing", score: combinedScore))
                continue
            }
            let reason = isCurrent ? "already_active" : assigned ? "explicit_assignment" : activationReason(document.activation.mode)
            let instructions = document.instructions.utf8.count <= inlineLimit ? document.instructions : nil
            let result = ResolvedSkillResult(
                id: document.id, version: document.version, kind: document.kind.rawValue,
                scope: controllingAssignment?.scope ?? document.scope.rawValue,
                enforcement: controllingAssignment?.required == true ? SkillEnforcement.required.rawValue : document.enforcement.rawValue,
                priority: controllingAssignment?.priority ?? document.priority,
                selectionReason: reason, score: combinedScore, instructions: instructions,
                contentIncluded: instructions != nil,
                resourceUri: SkillPackageResourceService.uri(
                    skillId: document.id,
                    version: document.version
                ),
                source: document.source
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
        let missing = Array(Set(bindings.filter(\.missing).map(\.capability))).sorted()
        let selectedIds = Set(selected.map { $0.1.id })
        let conflicts = selected.flatMap { pair in
            pair.1.conflictsWith.filter(selectedIds.contains).map { ResolutionConflict(skillId: pair.1.id, conflictsWith: $0, unresolved: true) }
        }
        let missingContext = [
            context.organization == nil ? "organization" : nil,
            context.workspace == nil ? "workspace" : nil,
            context.repository == nil ? "repository" : nil,
            context.task == nil ? "task" : nil
        ].compactMap { $0 }
        var nextActions: [ResolutionNextAction] = []
        for (result, _) in active {
            nextActions.append(.init(
                order: nextActions.count + 1,
                type: result.contentIncluded ? "apply_skill" : "read_skill",
                skillId: result.id,
                capability: nil,
                instruction: result.contentIncluded
                    ? "Apply the included \(result.id) instructions before continuing."
                    : "Read the complete \(result.id) package before continuing.",
                resourceUri: result.resourceUri
            ))
        }
        for binding in bindings.filter(\.missing).sorted(by: { $0.capability < $1.capability }) {
            let instruction: String
            switch MissingCapabilityFallback(rawValue: binding.fallback) {
            case .failActivation: instruction = "Do not activate the dependent skill until \(binding.capability) is available."
            case .warn: instruction = "Warn that \(binding.capability) is unavailable before continuing."
            case .returnDraft: instruction = "Return a draft for \(binding.capability); do not claim the external action occurred."
            case .requestProviderSelection: instruction = "Ask the user to select or connect a provider for \(binding.capability)."
            case .continueWithoutAction: instruction = "Continue without performing \(binding.capability), and state that no action occurred."
            case nil: instruction = "Report that \(binding.capability) is unavailable."
            }
            nextActions.append(.init(
                order: nextActions.count + 1, type: binding.fallback, skillId: binding.skillId,
                capability: binding.capability, instruction: instruction, resourceUri: nil
            ))
        }
        for conflict in conflicts.sorted(by: {
            $0.skillId == $1.skillId ? $0.conflictsWith < $1.conflictsWith : $0.skillId < $1.skillId
        }) {
            nextActions.append(.init(
                order: nextActions.count + 1, type: "resolve_conflict", skillId: conflict.skillId,
                capability: nil, instruction: "Resolve the conflict between \(conflict.skillId) and \(conflict.conflictsWith) before acting.",
                resourceUri: nil
            ))
        }

        let response = SkillResolutionResponse(
            traceId: traceId, activeSkills: active.map(\.0), suggestedTaskSkills: suggested.map(\.0),
            capabilityBindings: bindings, missingRequirements: missing, conflicts: conflicts,
            missingContext: missingContext, eventCanonical: event.map(canonicalEvents.contains),
            nextActions: nextActions, resolutionTrace: trace
        )
        try await recordTelemetry(response, request: request, projectId: projectId, db: db)
        return response
    }

    private static func ordered(_ lhs: ResolvedSkillResult, _ rhs: ResolvedSkillResult) -> Bool {
        let scopeOrder = ["task": 0, "repository": 1, "workspace": 2, "organization": 3, "global": 4]
        if lhs.enforcement != rhs.enforcement { return lhs.enforcement == "required" }
        if lhs.selectionReason != rhs.selectionReason {
            let explicit = ["already_active", "explicit_assignment"]
            if explicit.contains(lhs.selectionReason) != explicit.contains(rhs.selectionReason) { return explicit.contains(lhs.selectionReason) }
        }
        if (scopeOrder[lhs.scope] ?? 9) != (scopeOrder[rhs.scope] ?? 9) { return (scopeOrder[lhs.scope] ?? 9) < (scopeOrder[rhs.scope] ?? 9) }
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

    static func avoidMatch(_ conditions: [String], tokens queryTokens: Set<String>) -> Bool {
        conditions.contains { condition in
            let negativeTokens = tokens(condition)
            return !negativeTokens.isEmpty && negativeTokens.isSubset(of: queryTokens)
        }
    }

    static func activationMatches(_ mode: String, isCurrent: Bool, eventMatch: Bool, intentMatch: Bool) -> Bool {
        switch SkillActivationMode(rawValue: mode) {
        case .always: return true
        case .explicit: return isCurrent
        case .event: return eventMatch
        case .intent: return intentMatch
        case nil: return false
        }
    }

    static func scopeHasContext(_ scope: SkillScope, context: RuntimeContext) -> Bool {
        switch scope {
        case .global: return true
        case .organization: return context.organization != nil
        case .workspace: return context.workspace != nil
        case .repository: return context.repository != nil
        case .task: return context.task != nil
        }
    }

    private static func activationReason(_ mode: SkillActivationMode) -> String {
        switch mode {
        case .always: return "always_active"
        case .event: return "event_match"
        case .intent: return "intent_match"
        case .explicit: return "explicit_activation"
        }
    }

    private static func assignmentApplies(_ assignment: SkillAssignment, projectId: UUID, context: RuntimeContext) -> Bool {
        let target = assignment.targetId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return false }
        if assignment.targetType == "project" {
            return target == "project" || target.caseInsensitiveCompare(projectId.uuidString) == .orderedSame
        }
        guard assignment.targetType == assignment.scope else { return false }
        switch SkillScope(rawValue: assignment.scope) {
        case .global: return target == "*" || target == "global"
        case .organization: return context.organization == target
        case .workspace: return context.workspace == target
        case .repository: return context.repository == target
        case .task: return context.task == target
        case nil: return false
        }
    }

    private static func tokens(_ value: String) -> Set<String> {
        Set(value.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 2 })
    }

    static func bind(_ requirement: SkillRequirement, tools: [RuntimeToolInventoryItem]) -> CapabilityBindingResult {
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
