import Foundation

struct ParsedSkill {
    let path: String
    let name: String
    let description: String?
    let body: String
    let hash: String?
    let exposeAs: String?
    let useWhen: [String]?
    let avoidWhen: [String]?
    let riskLevel: String?
    let sideEffects: String?
    let repoSpecific: Bool?
}

struct SkillParser {
    static func parse(fileURL: URL, basePath: String) throws -> ParsedSkill {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SkillParserError.emptyFile
        }

        /// Line-aware parsing so multi-line YAML frontmatter works (`split(maxSplits: 1)` previously broke this).
        let lines = content.components(separatedBy: .newlines)

        var frontmatter: [String: String] = [:]
        var body = ""

        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            var i = 1
            var closed = false
            while i < lines.count {
                let line = lines[i]
                if line.trimmingCharacters(in: .whitespaces) == "---" {
                    i += 1
                    closed = true
                    break
                }
                if let colonIndex = line.firstIndex(of: ":") {
                    let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                    let value = String(line[line.index(after: colonIndex)...])
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    frontmatter[key] = Self.normalizeScalarString(value)
                }
                i += 1
            }
            guard closed else {
                throw SkillParserError.unclosedFrontmatter
            }
            body = lines[i...].joined(separator: "\n")
        } else {
            body = content
        }

        guard let rawName = frontmatter["name"] else {
            throw SkillParserError.missingName
        }
        let name = Self.normalizeScalarString(rawName)
        guard !name.isEmpty else {
            throw SkillParserError.missingName
        }

        let description: String? = {
            guard let d = frontmatter["description"] else { return nil }
            let t = Self.normalizeScalarString(d)
            return t.isEmpty ? nil : t
        }()
        let relativePath = fileURL.path.replacingOccurrences(of: basePath, with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let hash = content.data(using: .utf8).map { $0.base64EncodedString() }

        let exposeAs = frontmatter["expose_as"]
        let useWhen = parseStringArray(frontmatter["use_when"])
        let avoidWhen = parseStringArray(frontmatter["avoid_when"])
        let riskLevel = frontmatter["risk_level"]
        let sideEffects = frontmatter["side_effects"]
        let repoSpecific = frontmatter["repo_specific"].map { $0.lowercased() == "true" }

        return ParsedSkill(
            path: relativePath,
            name: name,
            description: description,
            body: body,
            hash: hash,
            exposeAs: exposeAs,
            useWhen: useWhen,
            avoidWhen: avoidWhen,
            riskLevel: riskLevel,
            sideEffects: sideEffects,
            repoSpecific: repoSpecific
        )
    }

    /// Trims whitespace/newlines and strips stray `\\r` from Windows-style line endings in single-line YAML values.
    private static func normalizeScalarString(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\r", with: "")
    }

    private static func parseStringArray(_ raw: String?) -> [String]? {
        guard let raw = raw, !raw.isEmpty else { return nil }
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("[") && s.hasSuffix("]") {
            s = String(s.dropFirst().dropLast())
        }
        let items = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return items.isEmpty ? nil : items
    }
}

enum SkillParserError: Error, LocalizedError {
    case emptyFile
    case missingName
    case unclosedFrontmatter

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "SKILL.md is empty"
        case .missingName:
            return "SKILL.md frontmatter is missing required \"name\" field"
        case .unclosedFrontmatter:
            return "SKILL.md frontmatter is missing closing --- delimiter"
        }
    }
}
