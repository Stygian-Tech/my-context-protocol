@testable import App
import Testing

@Suite("MCP metadata health tier")
struct McpMetadataHealthTests {
    @Test("Resource without URI is blocking")
    func resourceMissingUri() {
        let cs = CompiledSkill()
        cs.exposureType = "resource"
        cs.status = "ready"
        cs.yamlFrontmatterPresent = true
        cs.skillBody = "body"
        let schema = #"{"mimeType":"text/markdown"}"#
        let tier = McpMetadataHealth.tier(
            compiled: cs,
            schemaJson: schema,
            routing: .init(useWhen: ["a"], avoidWhen: nil, failureModes: nil, invokeFirst: nil)
        )
        #expect(tier == .blocking)
    }

    @Test("Ready tool with valid schema is ok")
    func toolOk() {
        let cs = CompiledSkill()
        cs.exposureType = "tool"
        cs.status = "ready"
        cs.yamlFrontmatterPresent = true
        cs.skillBody = "x"
        let schema = #"{"type":"object","properties":{}}"#
        let tier = McpMetadataHealth.tier(compiled: cs, schemaJson: schema, routing: .empty)
        #expect(tier == .ok)
    }

    @Test("Not publishable is blocking")
    func notPublishable() {
        let cs = CompiledSkill()
        cs.exposureType = "tool"
        cs.status = "not_publishable"
        cs.yamlFrontmatterPresent = true
        cs.skillBody = "x"
        let tier = McpMetadataHealth.tier(compiled: cs, schemaJson: "{}", routing: .empty)
        #expect(tier == .blocking)
    }

    @Test("metadataOnlyTier: invalid JSON is blocking without consulting status")
    func metadataInvalidJson() {
        let tier = McpMetadataHealth.metadataOnlyTier(
            exposureType: "tool",
            yamlFrontmatterPresent: true,
            skillBody: "x",
            schemaJson: "{not json",
            routing: .empty
        )
        #expect(tier == .blocking)
    }

    @Test("metadataOnlyTier: missing YAML front matter is warning when body and schema ok")
    func metadataMissingYaml() {
        let tier = McpMetadataHealth.metadataOnlyTier(
            exposureType: "tool",
            yamlFrontmatterPresent: false,
            skillBody: "x",
            schemaJson: #"{"type":"object"}"#,
            routing: .empty
        )
        #expect(tier == .warning)
    }

    @Test("resolvedPublishStatus: blocking tier forces not_publishable")
    func resolvedBlocking() {
        let r = McpMetadataHealth.resolvedPublishStatus(inferred: "ready", metadataTier: .blocking)
        #expect(r == "not_publishable")
    }

    @Test("resolvedPublishStatus: warning tier maps to needs_review when inferred ready")
    func resolvedWarning() {
        let r = McpMetadataHealth.resolvedPublishStatus(inferred: "ready", metadataTier: .warning)
        #expect(r == "needs_review")
    }

    @Test("resolvedPublishStatus: warning keeps not_publishable when inferred not_publishable")
    func resolvedWarningKeepsNotPublishable() {
        let r = McpMetadataHealth.resolvedPublishStatus(inferred: "not_publishable", metadataTier: .warning)
        #expect(r == "not_publishable")
    }
}
