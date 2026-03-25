import Testing
@testable import App

@Suite("MCP infrastructure")
struct MCPInfrastructureTests {
    @Test func mcpPathHasAtLeastOneSegment() {
        let parts = McpRoutePath.pathComponents()
        #expect(!parts.isEmpty)
    }

    @Test func resourceMetaRoundTrip() {
        let name = "My Skill"
        let json = CapabilitySchemaBuilder.resourceMetaJson(skillName: name)
        let parsed = CapabilitySchemaBuilder.parseResourceMeta(json)
        #expect(parsed != nil)
        #expect(parsed?.uri == CapabilitySchemaBuilder.resourceURI(skillName: name))
        #expect(parsed?.mimeType == "text/markdown")
    }

    @Test func toolInputSchemaDecodesForMCP() {
        let json = CapabilitySchemaBuilder.toolInputSchemaJson(description: "A skill", summary: "Summary line")
        let schema = InputSchema.fromCapabilitySchemaJson(json)
        #expect(schema.type == "object")
        #expect(schema.properties?["detail"] != nil)
    }
}
