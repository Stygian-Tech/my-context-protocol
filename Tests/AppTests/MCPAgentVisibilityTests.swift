import Foundation
import Testing
@testable import App

@Suite("MCP agent visibility")
struct MCPAgentVisibilityTests {
    @Test func protocolVersionNegotiation() {
        #expect(MCPProtocolVersion.negotiated(requested: "2025-06-18") == "2025-06-18")
        #expect(MCPProtocolVersion.negotiated(requested: "2024-11-05") == "2024-11-05")
        #expect(MCPProtocolVersion.negotiated(requested: "2099-01-01") == "2024-11-05")
        #expect(MCPProtocolVersion.negotiated(requested: nil) == "2024-11-05")
        #expect(MCPProtocolVersion.negotiated(requested: "  ") == "2024-11-05")
    }

    @Test func catalogRevisionBumps() {
        let hub = McpCatalogNotifications()
        let pid = UUID()
        #expect(hub.currentRevision(for: pid) == 0)
        hub.bumpCatalog(for: pid)
        #expect(hub.currentRevision(for: pid) == 1)
        hub.bumpCatalog(for: pid)
        #expect(hub.currentRevision(for: pid) == 2)
    }

    @Test func mergeRoutingHintsIntoDescription() {
        let hints = RoutingHints(
            useWhen: ["When planning"],
            avoidWhen: ["Trivial chat"],
            failureModes: ["Missing token"],
            invokeFirst: true
        )
        let merged = MCPAgentCopy.mergeRoutingHints(into: "Summary line", hints: hints)
        #expect(merged != nil)
        #expect(merged!.contains("Summary line"))
        #expect(merged!.contains("When to use:"))
        #expect(merged!.contains("Invoke first:"))
    }

    @Test func jsonRpcParamsDecodesProtocolVersion() throws {
        let json = #"{"protocolVersion":"2025-06-18","capabilities":{}}"#.data(using: .utf8)!
        let p = try JSONDecoder().decode(JSONRPCParams.self, from: json)
        #expect(p.protocolVersion == "2025-06-18")
    }

    @Test func eventPathSegments() {
        let base = McpRoutePath.pathComponents()
        #expect(!(base + ["events"]).isEmpty)
        #expect((base + ["events"]).last == "events")
    }
}
