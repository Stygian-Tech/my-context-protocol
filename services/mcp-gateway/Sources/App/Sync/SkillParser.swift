import Foundation
import Crypto
import Yams

struct ParsedSkill {
    let path: String
    let name: String
    let description: String?
    let body: String
    let hash: String?
    let exposeAs: String?
    let useWhen: [String]?
    let avoidWhen: [String]?
    /// Operational fallbacks when routing or tools fail (exposed in MCP resource metadata).
    let failureModes: [String]?
    /// When true, agents should consider loading this resource before other skills on the same task.
    let invokeFirst: Bool?
    let riskLevel: String?
    let sideEffects: String?
    let repoSpecific: Bool?
    let kind: SkillKind?
    let scope: SkillScope?
    let activation: SkillActivation?
    let enforcement: SkillEnforcement?
    let priority: Int?
    let requires: [SkillRequirement]
    let conflictsWith: [String]
    let version: String?
    let lifecycle: String?
    let rawFrontmatterJson: String?
    /// True when the file began with a closed `---` YAML front matter block (see Agent Skills layout).
    let hadYamlFrontmatter: Bool
}

struct SkillParser {
    private static let maxReadableSkillBytes = 1024 * 1024

    static func parse(fileURL: URL, basePath: String) throws -> ParsedSkill {
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw SkillParserError.notRegularFile
        }
        if let size = values.fileSize, size > maxReadableSkillBytes {
            throw SkillParserError.fileTooLarge
        }
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SkillParserError.emptyFile
        }

        /// Line-aware parsing so multi-line YAML frontmatter works (`split(maxSplits: 1)` previously broke this).
        let lines = content.components(separatedBy: .newlines)

        var frontmatter: [String: Any] = [:]
        var body = ""
        var hadYamlFrontmatter = false

        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            hadYamlFrontmatter = true
            var i = 1
            var closed = false
            let yamlStart = i
            while i < lines.count {
                let line = lines[i]
                if line.trimmingCharacters(in: .whitespaces) == "---" {
                    i += 1
                    closed = true
                    break
                }
                i += 1
            }
            guard closed else {
                throw SkillParserError.unclosedFrontmatter
            }
            let yaml = lines[yamlStart..<(i - 1)].joined(separator: "\n")
            do {
                frontmatter = try load(yaml: yaml) as? [String: Any] ?? [:]
            } catch {
                throw SkillParserError.invalidFrontmatter(error.localizedDescription)
            }
            body = lines[i...].joined(separator: "\n")
        } else {
            body = content
        }

        let relativePath = fileURL.path.replacingOccurrences(of: basePath, with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let name: String
        if hadYamlFrontmatter {
            guard let rawName = Self.string(frontmatter["name"]) else {
                throw SkillParserError.missingName
            }
            let n = Self.normalizeScalarString(rawName)
            guard !n.isEmpty else {
                throw SkillParserError.missingName
            }
            name = n
        } else {
            name = try Self.inferredNameFromParentDirectory(fileURL: fileURL)
        }

        let description: String? = {
            guard let d = Self.string(frontmatter["description"]) else { return nil }
            let t = Self.normalizeScalarString(d)
            return t.isEmpty ? nil : t
        }()
        let hash = content.data(using: .utf8).map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() }

        let exposeAs = Self.string(frontmatter["expose_as"])
        let useWhen = parseStringArray(frontmatter["use_when"])
        let avoidWhen = parseStringArray(frontmatter["avoid_when"])
        let failureModes = parseStringArray(frontmatter["failure_modes"])
        let invokeFirst = Self.bool(frontmatter["invoke_first"])
        let riskLevel = Self.string(frontmatter["risk_level"])
        let sideEffects = Self.string(frontmatter["side_effects"])
        let repoSpecific = Self.bool(frontmatter["repo_specific"])
        let kind = Self.string(frontmatter["kind"]).flatMap(SkillKind.init(rawValue:))
        let scope = Self.string(frontmatter["scope"]).flatMap(SkillScope.init(rawValue:))
        let enforcement = Self.string(frontmatter["enforcement"]).flatMap(SkillEnforcement.init(rawValue:))
        let priority = Self.int(frontmatter["priority"])
        let activation = Self.parseActivation(frontmatter["activation"], useWhen: useWhen)
        let requirements = Self.parseRequirements(frontmatter["requires"])
        let conflicts = parseStringArray(frontmatter["conflictsWith"] ?? frontmatter["conflicts_with"]) ?? []
        let version = Self.string(frontmatter["version"])
        let lifecycle = Self.string(frontmatter["lifecycle"])
        let rawFrontmatterJson: String? = {
            guard hadYamlFrontmatter,
                  JSONSerialization.isValidJSONObject(frontmatter),
                  let data = try? JSONSerialization.data(withJSONObject: frontmatter, options: [.sortedKeys]) else { return nil }
            return String(data: data, encoding: .utf8)
        }()

        return ParsedSkill(
            path: relativePath,
            name: name,
            description: description,
            body: body,
            hash: hash,
            exposeAs: exposeAs,
            useWhen: useWhen,
            avoidWhen: avoidWhen,
            failureModes: failureModes,
            invokeFirst: invokeFirst,
            riskLevel: riskLevel,
            sideEffects: sideEffects,
            repoSpecific: repoSpecific,
            kind: kind,
            scope: scope,
            activation: activation,
            enforcement: enforcement,
            priority: priority,
            requires: requirements,
            conflictsWith: conflicts,
            version: version,
            lifecycle: lifecycle,
            rawFrontmatterJson: rawFrontmatterJson,
            hadYamlFrontmatter: hadYamlFrontmatter
        )
    }

    /// Parent folder name for `…/skill-name/SKILL.md` when there is no YAML `name` field.
    private static func inferredNameFromParentDirectory(fileURL: URL) throws -> String {
        let parent = fileURL.deletingLastPathComponent().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !parent.isEmpty, parent != ".", parent != "/" else {
            throw SkillParserError.cannotInferNameWithoutFrontmatter
        }
        let normalized = normalizeScalarString(parent)
        guard !normalized.isEmpty else {
            throw SkillParserError.cannotInferNameWithoutFrontmatter
        }
        return normalized
    }

    /// Trims whitespace/newlines and strips stray `\\r` from Windows-style line endings in single-line YAML values.
    private static func normalizeScalarString(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\r", with: "")
    }

    private static func string(_ raw: Any?) -> String? {
        if let value = raw as? String { return normalizeScalarString(value) }
        if let value = raw as? NSNumber { return value.stringValue }
        return nil
    }

    private static func bool(_ raw: Any?) -> Bool? {
        if let value = raw as? Bool { return value }
        return string(raw).flatMap { ["true", "yes", "1"].contains($0.lowercased()) ? true : (["false", "no", "0"].contains($0.lowercased()) ? false : nil) }
    }

    private static func int(_ raw: Any?) -> Int? {
        if let value = raw as? Int { return value }
        if let value = raw as? NSNumber { return value.intValue }
        return string(raw).flatMap(Int.init)
    }

    private static func parseStringArray(_ raw: Any?) -> [String]? {
        if let values = raw as? [Any] {
            let result = values.compactMap(string).filter { !$0.isEmpty }
            return result.isEmpty ? nil : result
        }
        guard let raw = string(raw), !raw.isEmpty else { return nil }
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("[") && s.hasSuffix("]") {
            s = String(s.dropFirst().dropLast())
        }
        let items = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return items.isEmpty ? nil : items
    }

    private static func parseActivation(_ raw: Any?, useWhen: [String]?) -> SkillActivation? {
        guard let object = raw as? [String: Any] else { return nil }
        guard let modeRaw = string(object["mode"]), let mode = SkillActivationMode(rawValue: modeRaw) else { return nil }
        return SkillActivation(
            mode: mode,
            intents: parseStringArray(object["intents"]) ?? useWhen ?? [],
            events: parseStringArray(object["events"]) ?? [],
            tags: parseStringArray(object["tags"]) ?? [],
            examples: parseStringArray(object["examples"]) ?? []
        )
    }

    private static func parseRequirements(_ raw: Any?) -> [SkillRequirement] {
        guard let rows = raw as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let capability = string(row["capability"]), !capability.isEmpty else { return nil }
            let required = bool(row["required"]) ?? true
            let fallback = string(row["on_missing"]).flatMap(MissingCapabilityFallback.init(rawValue:)) ?? (required ? .failActivation : .warn)
            return SkillRequirement(capability: capability, required: required, onMissing: fallback)
        }
    }
}

enum SkillParserError: Error, LocalizedError, Equatable {
    case emptyFile
    case missingName
    case unclosedFrontmatter
    case cannotInferNameWithoutFrontmatter
    case invalidFrontmatter(String)
    case notRegularFile
    case fileTooLarge

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "SKILL.md is empty"
        case .missingName:
            return "SKILL.md frontmatter is missing required \"name\" field"
        case .unclosedFrontmatter:
            return "SKILL.md frontmatter is missing closing --- delimiter"
        case .cannotInferNameWithoutFrontmatter:
            return "SKILL.md has no YAML front matter: place the file in a directory whose name is a valid skill slug (e.g. my-skill/SKILL.md), or add a \"name\" field under leading --- front matter"
        case .invalidFrontmatter(let detail):
            return "SKILL.md contains invalid YAML front matter: \(detail)"
        case .notRegularFile:
            return "SKILL.md must be a regular file inside the repository"
        case .fileTooLarge:
            return "SKILL.md exceeds size limit"
        }
    }
}
