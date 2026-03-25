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

    @Test func resourceMetaAgentHintsRoundTrip() {
        let json = CapabilitySchemaBuilder.resourceMetaJson(
            skillName: "linear-workflow",
            useWhen: ["Starting implementation", "Plan mode"],
            avoidWhen: ["Pure Q&A with no repo access"],
            failureModes: ["No issue on branch — note and proceed"],
            invokeFirst: true
        )
        let parsed = CapabilitySchemaBuilder.parseResourceMeta(json)
        #expect(parsed?.useWhen?.count == 2)
        #expect(parsed?.avoidWhen?.count == 1)
        #expect(parsed?.failureModes?.count == 1)
        #expect(parsed?.invokeFirst == true)
        let preamble = CapabilitySchemaBuilder.resourceReadPreamble(meta: parsed!, skillSummary: "Keeps Linear in sync.")
        #expect(preamble != nil)
        #expect(preamble!.contains("Read when:"))
        #expect(preamble!.contains("Invoke first:"))
    }

    @Test func toolInputSchemaDecodesForMCP() {
        let json = CapabilitySchemaBuilder.toolInputSchemaJson(description: "A skill", summary: "Summary line")
        let schema = InputSchema.fromCapabilitySchemaJson(json)
        #expect(schema.type == "object")
        #expect(schema.properties?["detail"] != nil)
    }
}
