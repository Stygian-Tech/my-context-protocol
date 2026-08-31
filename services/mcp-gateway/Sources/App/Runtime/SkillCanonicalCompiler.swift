import Fluent
import Foundation
import Vapor
import Yams

struct SkillRuntimeOverridePatch: Codable, Content, Equatable, Sendable {
    var exposure: String?
    var kind: SkillKind?
    var scope: SkillScope?
    var activation: SkillActivation?
    var enforcement: SkillEnforcement?
    var priority: Int?
    var requires: [SkillRequirement]?
    var avoidWhen: [String]?
    var conflictsWith: [String]?
    var version: String?
    var lifecycle: String?

    enum CodingKeys: String, CodingKey {
        case exposure, kind, scope, activation, enforcement, priority, requires, version, lifecycle
        case avoidWhen = "avoid_when"
        case conflictsWith = "conflicts_with"
    }
}

struct SkillSourcePolicy: Codable, Equatable, Sendable {
    var baseChecksum: String?
    var metadata: SkillRuntimeOverridePatch

    enum CodingKeys: String, CodingKey {
        case baseChecksum = "base_checksum"
        case metadata
    }
}

struct SkillSourcePolicyState: Sendable {
    var policy: SkillSourcePolicy
    var rawJson: String
    var stale: Bool
}

enum SkillCanonicalCompiler {
    static func compile(
        parsed: ParsedSkill,
        package: SkillPackage,
        repository: String?,
        revision: String?,
        sourcePolicy: SkillSourcePolicy? = nil,
        override: SkillRuntimeOverridePatch? = nil
    ) -> (document: CompiledSkillDocument, questions: [SkillClarificationQuestion]) {
        var missing: [String] = []
        // A standard Agent Skills package only requires name and description. Portable runtime
        // fields are optional and receive safe, useful defaults instead of blocking publication.
        if !parsed.hadYamlFrontmatter {
            if parsed.kind == nil, sourcePolicy?.metadata.kind == nil, override?.kind == nil { missing.append("kind") }
            if parsed.scope == nil, sourcePolicy?.metadata.scope == nil, override?.scope == nil { missing.append("scope") }
            if parsed.activation == nil, sourcePolicy?.metadata.activation == nil, override?.activation == nil { missing.append("activation") }
            if parsed.enforcement == nil, sourcePolicy?.metadata.enforcement == nil, override?.enforcement == nil { missing.append("enforcement") }
            if parsed.version == nil, sourcePolicy?.metadata.version == nil, override?.version == nil { missing.append("version") }
        }

        let activation = override?.activation ?? sourcePolicy?.metadata.activation ?? parsed.activation ?? SkillActivation(
            mode: parsed.hadYamlFrontmatter ? .intent : .explicit,
            intents: parsed.useWhen ?? [],
            events: [],
            tags: [],
            examples: []
        )
        let checksum = parsed.hash ?? "unknown"
        let description = parsed.description ?? String(parsed.body.prefix(200))
        let generatedVersion = version(revision: revision, checksum: checksum)
        let document = CompiledSkillDocument(
            schemaVersion: CompiledSkillDocument.currentSchemaVersion,
            id: package.name,
            name: package.name,
            description: description,
            kind: override?.kind ?? sourcePolicy?.metadata.kind ?? parsed.kind ?? .task,
            scope: override?.scope ?? sourcePolicy?.metadata.scope ?? parsed.scope ?? .task,
            activation: activation,
            avoidWhen: override?.avoidWhen ?? sourcePolicy?.metadata.avoidWhen ?? parsed.avoidWhen,
            enforcement: override?.enforcement ?? sourcePolicy?.metadata.enforcement ?? parsed.enforcement ?? .advisory,
            priority: min(100, max(0, override?.priority ?? sourcePolicy?.metadata.priority ?? parsed.priority ?? 50)),
            requires: override?.requires ?? sourcePolicy?.metadata.requires ?? parsed.requires,
            conflictsWith: override?.conflictsWith ?? sourcePolicy?.metadata.conflictsWith ?? parsed.conflictsWith,
            instructions: parsed.body,
            source: SkillSource(repository: repository, path: parsed.path, revision: revision, checksum: checksum),
            version: override?.version ?? sourcePolicy?.metadata.version ?? parsed.version ?? generatedVersion,
            lifecycle: override?.lifecycle ?? sourcePolicy?.metadata.lifecycle ?? parsed.lifecycle,
            standardFrontmatterJson: parsed.rawFrontmatterJson,
            validation: SkillValidationState(
                clarificationRequired: !missing.isEmpty,
                missingFields: missing,
                warnings: parsed.hadYamlFrontmatter ? [] : ["No YAML front matter; conservative runtime defaults applied."]
            )
        )
        return (document, questionsForRuntime(fields: missing))
    }

    static func sourcePolicies(repoRoot: URL) throws -> [String: SkillSourcePolicyState] {
        let url = repoRoot.appendingPathComponent(".mycontext/skills.yaml")
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw SkillSourcePolicyError.unsafeFile
        }
        guard (values.fileSize ?? 0) <= 256 * 1024 else {
            throw SkillSourcePolicyError.fileTooLarge
        }
        let yaml = try String(contentsOf: url, encoding: .utf8)
        let loaded: Any?
        do {
            loaded = try load(yaml: yaml)
        } catch {
            throw SkillSourcePolicyError.invalidYAML(error.localizedDescription)
        }
        guard let root = loaded as? [String: Any] else {
            throw SkillSourcePolicyError.invalidRoot("the document root must be a mapping")
        }
        guard let version = Self.integer(root["version"]) else {
            throw SkillSourcePolicyError.invalidRoot("version is required and must be an integer")
        }
        guard version == 1 else {
            throw SkillSourcePolicyError.unsupportedVersion(version)
        }
        guard root.keys.contains("skills"), let skills = root["skills"] as? [String: Any] else {
            throw SkillSourcePolicyError.invalidRoot("skills is required and must be a mapping")
        }
        var result: [String: SkillSourcePolicyState] = [:]
        for (skillId, value) in skills.sorted(by: { $0.key < $1.key }) {
            guard Self.isValidPolicySkillId(skillId) else {
                throw SkillSourcePolicyError.invalidEntry(skillId, "skill id must be a lowercase ASCII slug of at most 64 characters")
            }
            guard let object = value as? [String: Any] else {
                throw SkillSourcePolicyError.invalidEntry(skillId, "entry must be a mapping")
            }
            guard JSONSerialization.isValidJSONObject(object) else {
                throw SkillSourcePolicyError.invalidEntry(skillId, "entry contains values that cannot be represented as JSON")
            }
            let data: Data
            do {
                data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            } catch {
                throw SkillSourcePolicyError.invalidEntry(skillId, error.localizedDescription)
            }
            let decoded: SkillSourcePolicy
            do {
                decoded = try JSONDecoder().decode(SkillSourcePolicy.self, from: data)
            } catch {
                throw SkillSourcePolicyError.invalidEntry(skillId, Self.decodingDescription(error))
            }
            if let exposure = decoded.metadata.exposure,
               !["tool", "resource", "prompt"].contains(exposure) {
                throw SkillSourcePolicyError.invalidEntry(skillId, "metadata.exposure must be tool, resource, or prompt")
            }
            if let priority = decoded.metadata.priority, !(0...100).contains(priority) {
                throw SkillSourcePolicyError.invalidEntry(skillId, "metadata.priority must be between 0 and 100")
            }
            guard let raw = String(data: data, encoding: .utf8) else {
                throw SkillSourcePolicyError.invalidEntry(skillId, "entry could not be encoded as UTF-8")
            }
            result[skillId] = .init(policy: decoded, rawJson: raw, stale: false)
        }
        return result
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber {
            let double = value.doubleValue
            guard double.rounded() == double else { return nil }
            return value.intValue
        }
        return nil
    }

    private static func isValidPolicySkillId(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 64 else { return false }
        let range = NSRange(value.startIndex..., in: value)
        guard let match = Validator.allowedNamePattern.firstMatch(in: value, range: range),
              NSEqualRanges(match.range, range) else { return false }
        return !MCPConstants.isReservedRuntimeToolName(value)
    }

    private static func decodingDescription(_ error: Error) -> String {
        switch error {
        case let DecodingError.typeMismatch(_, context),
             let DecodingError.valueNotFound(_, context),
             let DecodingError.keyNotFound(_, context),
             let DecodingError.dataCorrupted(context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return path.isEmpty ? context.debugDescription : "\(path): \(context.debugDescription)"
        default:
            return error.localizedDescription
        }
    }

    private static func version(revision: String?, checksum: String) -> String {
        let trimmed = revision?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let revisionPart = trimmed.isEmpty ? "unversioned" : trimmed
        return "\(revisionPart)+\(checksum.prefix(12))"
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

enum SkillSourcePolicyError: Error, LocalizedError, Equatable {
    case unsafeFile
    case fileTooLarge
    case invalidYAML(String)
    case invalidRoot(String)
    case unsupportedVersion(Int)
    case invalidEntry(String, String)

    var errorDescription: String? {
        switch self {
        case .unsafeFile:
            return ".mycontext/skills.yaml must be a regular, non-symbolic-link file"
        case .fileTooLarge:
            return ".mycontext/skills.yaml exceeds the 256 KiB size limit"
        case .invalidYAML(let reason):
            return ".mycontext/skills.yaml contains invalid YAML: \(reason)"
        case .invalidRoot(let reason):
            return ".mycontext/skills.yaml is invalid: \(reason)"
        case .unsupportedVersion(let version):
            return ".mycontext/skills.yaml version \(version) is unsupported; expected version 1"
        case .invalidEntry(let skillId, let reason):
            return ".mycontext/skills.yaml entry skills.\(skillId) is invalid: \(reason)"
        }
    }
}
