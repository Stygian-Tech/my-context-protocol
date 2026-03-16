import Foundation

struct ValidationReport {
    let isValid: Bool
    let errors: [ValidationError]
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

        if skill.name.isEmpty {
            errors.append(ValidationError(path: skill.path, message: "name cannot be empty", line: nil))
        }

        if !skill.name.isEmpty {
            let nameRange = NSRange(skill.name.startIndex..., in: skill.name)
            if nameRange.location != NSNotFound,
               Self.allowedNamePattern.firstMatch(in: skill.name, range: nameRange) == nil {
                errors.append(ValidationError(
                    path: skill.path,
                    message: "name must be lowercase with hyphens only: \(skill.name)",
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
            errors: errors
        )
    }
}
