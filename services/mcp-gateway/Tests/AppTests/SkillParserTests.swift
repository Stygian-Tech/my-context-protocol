import Foundation
import Testing
@testable import App

@Suite("SkillParser")
struct SkillParserTests {
    @Test func infersNameWhenNoYamlFrontMatter() throws {
        let tmp = FileManager.default.temporaryDirectory
        let root = tmp.appendingPathComponent("skill-parse-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let skillDir = root.appendingPathComponent("my-skill")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let file = skillDir.appendingPathComponent("SKILL.md")
        try "Hello body content".write(to: file, atomically: true, encoding: .utf8)

        let parsed = try SkillParser.parse(fileURL: file, basePath: root.path)
        #expect(parsed.name == "my-skill")
        #expect(parsed.hadYamlFrontmatter == false)
        #expect(parsed.path.hasSuffix("my-skill/SKILL.md"))
        #expect(parsed.body.contains("Hello body"))
    }

    @Test func yamlFrontMatterSetsFlag() throws {
        let tmp = FileManager.default.temporaryDirectory
        let root = tmp.appendingPathComponent("skill-parse-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let skillDir = root.appendingPathComponent("boxed")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let file = skillDir.appendingPathComponent("SKILL.md")
        let md = """
        ---
        name: other-name
        description: Hi
        ---

        Body here
        """
        try md.write(to: file, atomically: true, encoding: .utf8)

        let parsed = try SkillParser.parse(fileURL: file, basePath: root.path)
        #expect(parsed.hadYamlFrontmatter == true)
        #expect(parsed.name == "other-name")
        #expect(parsed.description == "Hi")
    }

    @Test func validatorEmitsWarningWhenNoFrontmatter() throws {
        let tmp = FileManager.default.temporaryDirectory
        let root = tmp.appendingPathComponent("skill-parse-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let skillDir = root.appendingPathComponent("warn-skill")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let file = skillDir.appendingPathComponent("SKILL.md")
        try "x".write(to: file, atomically: true, encoding: .utf8)

        let parsed = try SkillParser.parse(fileURL: file, basePath: root.path)
        let report = Validator.validate(parsed)
        #expect(report.warnings.count == 1)
        #expect(report.warnings[0].message.contains("No YAML front matter"))
    }

    @Test func parsesPortableRuntimeFrontmatterAndCompilesDeterministically() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("portable-skill-\(UUID().uuidString)")
        let skillDir = root.appendingPathComponent("incidental-issues")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = skillDir.appendingPathComponent("SKILL.md")
        try """
        ---
        name: incidental-issues
        description: Preserve unrelated follow-up work.
        kind: operating
        scope: workspace
        enforcement: required
        priority: 80
        version: 1.0.0
        activation:
          mode: event
          events:
            - non_blocking_issue_discovered
          intents: [follow-up work]
        requires:
          - capability: issue.create
            required: true
            on_missing: return_draft
        conflictsWith: [ignore-incidental-issues]
        ---
        # Incidental issues
        Continue the original task after preserving the issue.
        """.write(to: file, atomically: true, encoding: .utf8)

        let parsed = try SkillParser.parse(fileURL: file, basePath: root.path)
        #expect(parsed.kind == .operating)
        #expect(parsed.scope == .workspace)
        #expect(parsed.activation?.events == ["non_blocking_issue_discovered"])
        #expect(parsed.requires.first?.capability == "issue.create")
        #expect(parsed.requires.first?.onMissing == .returnDraft)
        #expect(parsed.hash?.count == 64)

        let package = SkillPackage(releaseId: UUID(), path: parsed.path, name: parsed.name, validationStatus: "valid")
        let first = SkillCanonicalCompiler.compile(parsed: parsed, package: package, repository: "stygian/skills", revision: "abc")
        let second = SkillCanonicalCompiler.compile(parsed: parsed, package: package, repository: "stygian/skills", revision: "abc")
        #expect(first.document == second.document)
        #expect(first.questions.isEmpty)
        #expect(first.document.activation.mode == .event)
        #expect(first.document.enforcement == .required)
    }

    @Test func legacySkillRequiresClarificationAndUsesExplicitActivation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-skill-\(UUID().uuidString)")
        let skillDir = root.appendingPathComponent("legacy")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = skillDir.appendingPathComponent("SKILL.md")
        try "Legacy markdown".write(to: file, atomically: true, encoding: .utf8)
        let parsed = try SkillParser.parse(fileURL: file, basePath: root.path)
        let package = SkillPackage(releaseId: UUID(), path: parsed.path, name: parsed.name, validationStatus: "valid")
        let result = SkillCanonicalCompiler.compile(parsed: parsed, package: package, repository: nil, revision: nil)
        #expect(result.document.activation.mode == .explicit)
        #expect(result.document.validation.clarificationRequired)
        #expect(Set(result.document.validation.missingFields) == Set(["kind", "scope", "activation", "enforcement", "version"]))
    }

    @Test func rejectsSymlinkedSkillFiles() throws {
        let tmp = FileManager.default.temporaryDirectory
        let root = tmp.appendingPathComponent("skill-parse-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let target = root.appendingPathComponent("target.md")
        try "secret body".write(to: target, atomically: true, encoding: .utf8)
        let skillDir = root.appendingPathComponent("symlink-skill")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let link = skillDir.appendingPathComponent("SKILL.md")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: target.path)

        #expect(throws: SkillParserError.notRegularFile) {
            _ = try SkillParser.parse(fileURL: link, basePath: root.path)
        }
    }

    @Test func rejectsOversizedSkillFilesBeforeParsing() throws {
        let tmp = FileManager.default.temporaryDirectory
        let root = tmp.appendingPathComponent("skill-parse-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let skillDir = root.appendingPathComponent("big-skill")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let file = skillDir.appendingPathComponent("SKILL.md")
        let body = String(repeating: "a", count: Validator.maxFileSize + 1)
        try body.write(to: file, atomically: true, encoding: .utf8)

        #expect(throws: SkillParserError.fileTooLarge) {
            _ = try SkillParser.parse(fileURL: file, basePath: root.path)
        }
    }
}
