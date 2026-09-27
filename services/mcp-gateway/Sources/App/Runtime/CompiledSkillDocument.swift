import Foundation

enum SkillKind: String, Codable, CaseIterable, Sendable { case operating, task, toolUse = "tool-use", reference }
enum SkillScope: String, Codable, CaseIterable, Sendable { case global, organization, workspace, repository, task }
enum SkillActivationMode: String, Codable, CaseIterable, Sendable { case always, intent, event, explicit }
enum SkillEnforcement: String, Codable, CaseIterable, Sendable { case advisory, required }
enum MissingCapabilityFallback: String, Codable, CaseIterable, Sendable {
    case failActivation = "fail_activation", warn, returnDraft = "return_draft"
    case requestProviderSelection = "request_provider_selection", continueWithoutAction = "continue_without_action"
}

struct SkillActivation: Codable, Equatable, Sendable {
    var mode: SkillActivationMode
    var intents: [String]
    var events: [String]
    var tags: [String]
    var examples: [String]
}

struct SkillRequirement: Codable, Equatable, Sendable {
    var capability: String
    var required: Bool
    var onMissing: MissingCapabilityFallback

    enum CodingKeys: String, CodingKey {
        case capability, required
        case onMissing = "on_missing"
    }

    private enum LegacyCodingKeys: String, CodingKey { case onMissing }

    init(capability: String, required: Bool, onMissing: MissingCapabilityFallback) {
        self.capability = capability
        self.required = required
        self.onMissing = onMissing
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        capability = try values.decode(String.self, forKey: .capability)
        required = try values.decode(Bool.self, forKey: .required)
        if let value = try values.decodeIfPresent(MissingCapabilityFallback.self, forKey: .onMissing) {
            onMissing = value
        } else {
            let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
            onMissing = try legacy.decode(MissingCapabilityFallback.self, forKey: .onMissing)
        }
    }
}

struct SkillSource: Codable, Equatable, Sendable {
    var repository: String?
    var path: String
    var revision: String?
    var checksum: String
}

struct SkillValidationState: Codable, Equatable, Sendable {
    var clarificationRequired: Bool
    var missingFields: [String]
    var warnings: [String]
}

struct CompiledSkillDocument: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var id: String
    var name: String
    var description: String
    var kind: SkillKind
    var scope: SkillScope
    var activation: SkillActivation
    /// Negative routing hints are part of the canonical document so every resolver surface applies them.
    var avoidWhen: [String]? = nil
    var enforcement: SkillEnforcement
    var priority: Int
    var requires: [SkillRequirement]
    var conflictsWith: [String]
    var instructions: String
    var source: SkillSource
    var version: String
    var lifecycle: String?
    /// Lossless JSON copy of standards-compliant front matter, including optional fields this
    /// runtime does not interpret yet (for example license, compatibility, metadata, allowed-tools).
    var standardFrontmatterJson: String? = nil
    var validation: SkillValidationState
}

struct SkillClarificationQuestion: Codable, Equatable, Sendable {
    var field: String
    var question: String
    var options: [String]
    var required: Bool
}

enum SkillRuntimeJSON {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    static func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? encoder.encode(value) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func decode<T: Decodable>(_ type: T.Type, from value: String?) -> T? {
        guard let value, let data = value.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
