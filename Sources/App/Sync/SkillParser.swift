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

        let parts = content.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count >= 1 else {
            throw SkillParserError.emptyFile
        }

        var frontmatter: [String: String] = [:]
        var body = ""

        if parts[0].trimmingCharacters(in: .whitespaces) == "---" {
            var endIndex = 1
            while endIndex < parts.count {
                let line = String(parts[endIndex])
                if line.trimmingCharacters(in: .whitespaces) == "---" {
                    endIndex += 1
                    break
                }
                if let colonIndex = line.firstIndex(of: ":") {
                    let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                    let value = String(line[line.index(after: colonIndex)...])
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    frontmatter[key] = value
                }
                endIndex += 1
            }
            if endIndex < parts.count {
                body = parts[endIndex...].joined(separator: "\n")
            }
        } else {
            body = content
        }

        guard let name = frontmatter["name"] else {
            throw SkillParserError.missingName
        }

        let description = frontmatter["description"]
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

enum SkillParserError: Error {
    case emptyFile
    case missingName
}
