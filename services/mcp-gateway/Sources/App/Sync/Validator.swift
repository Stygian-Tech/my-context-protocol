import Foundation

struct ValidationReport {
    let isValid: Bool
    let errors: [ValidationError]
    let warnings: [ValidationError]
}

struct ValidationError {
    let path: String
    let message: String
    let line: Int?
}

struct Validator {
    static let maxFileSize = 1024 * 1024
    static let allowedNamePattern = try! NSRegularExpression(pattern: "^[a-z0-9][a-z0-9-]*$")

    static func validate(_ skill: ParsedSkill) -> ValidationReport {
        var errors: [ValidationError] = []
        var warnings: [ValidationError] = []

        if !skill.hadYamlFrontmatter {
            warnings.append(ValidationError(
                path: skill.path,
                message: "No YAML front matter; skill name was inferred from the parent directory.",
                line: nil
            ))
        }

        if skill.name.isEmpty {
            errors.append(ValidationError(path: skill.path, message: "name cannot be empty", line: nil))
        }

        if !skill.name.isEmpty {
            let nsName = skill.name as NSString
            let full = NSRange(location: 0, length: nsName.length)
            let ok: Bool
            if let m = Self.allowedNamePattern.firstMatch(in: skill.name, options: [], range: full) {
                ok = NSEqualRanges(m.range, full)
            } else {
                ok = false
            }
            if !ok {
                errors.append(ValidationError(
                    path: skill.path,
                    message: "name must be lowercase ASCII slug (letters, digits, single hyphens): got \"\(skill.name)\"",
                    line: nil
                ))
            }
        }

        if skill.name.count > 64 {
            errors.append(ValidationError(
                path: skill.path,
                message: "name must be 64 characters or less",
                line: nil
            ))
        }

        if skill.body.count > Self.maxFileSize {
            errors.append(ValidationError(
                path: skill.path,
                message: "SKILL.md body exceeds size limit",
                line: nil
            ))
        }

        return ValidationReport(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings
        )
    }
}
