import Foundation

struct ParsedSkill {
    let path: String
    let name: String
    let description: String?
    let body: String
    let hash: String?
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

        return ParsedSkill(
            path: relativePath,
            name: name,
            description: description,
            body: body,
            hash: hash
        )
    }
}

enum SkillParserError: Error {
    case emptyFile
    case missingName
}
