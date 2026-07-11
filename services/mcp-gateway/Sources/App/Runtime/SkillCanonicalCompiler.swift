import Fluent
import Foundation
import Vapor

struct SkillRuntimeOverridePatch: Codable, Content, Sendable {
    var kind: SkillKind?
    var scope: SkillScope?
    var activation: SkillActivation?
    var enforcement: SkillEnforcement?
    var priority: Int?
    var requires: [SkillRequirement]?
    var conflictsWith: [String]?
    var version: String?
    var lifecycle: String?
}

enum SkillCanonicalCompiler {
    static func compile(
        parsed: ParsedSkill,
        package: SkillPackage,
        repository: String?,
        revision: String?,
        override: SkillRuntimeOverridePatch? = nil
    ) -> (document: CompiledSkillDocument, questions: [SkillClarificationQuestion]) {
        var missing: [String] = []
        if parsed.kind == nil, override?.kind == nil { missing.append("kind") }
        if parsed.scope == nil, override?.scope == nil { missing.append("scope") }
        if parsed.activation == nil, override?.activation == nil { missing.append("activation") }
        if parsed.enforcement == nil, override?.enforcement == nil { missing.append("enforcement") }
        if parsed.version == nil, override?.version == nil { missing.append("version") }

        let activation = override?.activation ?? parsed.activation ?? SkillActivation(
            mode: .explicit,
            intents: parsed.useWhen ?? [],
            events: [],
            tags: [],
            examples: []
        )
        let checksum = parsed.hash ?? "unknown"
        let description = parsed.description ?? String(parsed.body.prefix(200))
        let document = CompiledSkillDocument(
            schemaVersion: CompiledSkillDocument.currentSchemaVersion,
            id: package.name,
            name: package.name,
            description: description,
            kind: override?.kind ?? parsed.kind ?? .reference,
            scope: override?.scope ?? parsed.scope ?? .task,
            activation: activation,
            enforcement: override?.enforcement ?? parsed.enforcement ?? .advisory,
            priority: min(100, max(0, override?.priority ?? parsed.priority ?? 50)),
            requires: override?.requires ?? parsed.requires,
            conflictsWith: override?.conflictsWith ?? parsed.conflictsWith,
            instructions: parsed.body,
            source: SkillSource(repository: repository, path: parsed.path, revision: revision, checksum: checksum),
            version: override?.version ?? parsed.version ?? "0.0.0",
            lifecycle: override?.lifecycle ?? parsed.lifecycle,
            validation: SkillValidationState(
                clarificationRequired: !missing.isEmpty,
                missingFields: missing,
                warnings: parsed.hadYamlFrontmatter ? [] : ["No YAML front matter; conservative runtime defaults applied."]
            )
        )
        return (document, questionsForRuntime(fields: missing))
    }

    static func questionsForRuntime(fields: [String]) -> [SkillClarificationQuestion] {
        fields.compactMap { field in
            switch field {
            case "kind": return .init(field: field, question: "What kind of skill is this?", options: SkillKind.allCases.map(\.rawValue), required: true)
            case "scope": return .init(field: field, question: "At which scope may this skill activate?", options: SkillScope.allCases.map(\.rawValue), required: true)
            case "activation": return .init(field: field, question: "How should this skill activate?", options: SkillActivationMode.allCases.map(\.rawValue), required: true)
            case "enforcement": return .init(field: field, question: "Is this guidance advisory or required?", options: SkillEnforcement.allCases.map(\.rawValue), required: true)
            case "version": return .init(field: field, question: "Which semantic version identifies this skill?", options: [], required: true)
            default: return nil
            }
        }
    }
}
