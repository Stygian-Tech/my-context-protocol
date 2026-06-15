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
}
