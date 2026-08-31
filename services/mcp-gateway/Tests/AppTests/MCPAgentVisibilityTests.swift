import Foundation
import MCPServerKit
import Testing
@testable import App

@Suite("MCP agent visibility")
struct MCPAgentVisibilityTests {
    @Test func protocolVersionNegotiation() {
        #expect(MCPServerKit.MCPProtocolVersion.negotiated(requested: "2025-11-25") == "2025-11-25")
        #expect(MCPServerKit.MCPProtocolVersion.negotiated(requested: "2025-03-26") == "2025-03-26")
        #expect(MCPServerKit.MCPProtocolVersion.negotiated(requested: "2025-06-18") == "2025-06-18")
        #expect(MCPServerKit.MCPProtocolVersion.negotiated(requested: "2024-11-05") == "2024-11-05")
        #expect(MCPServerKit.MCPProtocolVersion.negotiated(requested: "2099-01-01") == "2025-11-25")
        #expect(MCPServerKit.MCPProtocolVersion.negotiated(requested: nil) == "2025-11-25")
        #expect(MCPServerKit.MCPProtocolVersion.negotiated(requested: "  ") == "2025-11-25")
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
        let json = #"{"protocolVersion":"2025-11-25","capabilities":{}}"#.data(using: .utf8)!
        let p = try JSONDecoder().decode(JSONRPCParams.self, from: json)
        #expect(p.protocolVersion == "2025-11-25")
    }

    @Test func initializeCopyAdvertisesCanonicalBootstrapTool() {
        let copy = MCPAgentCopy.initializeInstructions(projectName: "Example", projectDashboardURL: nil)
        #expect(copy.contains("`resolve_context`"))
        #expect(copy.contains("`get_skill`"))
        #expect(copy.contains("`report_skill_feedback`"))
        #expect(!copy.contains("`mycontext_catalog`"))
        #expect(!copy.contains("`discover_skills`"))
        #expect(!copy.contains("`list_capabilities`"))
    }

    @Test func publicAndReservedRuntimeToolNamesAreStable() {
        #expect(MCPConstants.runtimeToolNames == ["resolve_context", "get_skill", "report_skill_feedback"])
        #expect(Set(MCPConstants.hiddenRuntimeToolAliases) == ["mycontext_catalog", "discover_skills", "list_capabilities"])
        #expect(MCPConstants.callableRuntimeToolNames.count == 6)
        for name in MCPConstants.callableRuntimeToolNames {
            #expect(MCPConstants.isReservedRuntimeToolName(name))
        }
    }

    @Test func runtimeSchemasAreRequiredTypedAndStructured() {
        let resolve = CapabilitySchemaBuilder.runtimeToolInputSchema(name: "resolve_context")
        #expect(resolve.required == ["request"])
        #expect(resolve.additionalProperties == false)
        #expect(resolve.properties?["available_tools"]?.type == "array")
        #expect(resolve.properties?["available_tools"]?.items?.type == "object")
        #expect(resolve.properties?["context"]?.type == "object")
        #expect(resolve.properties?["context"]?.properties?["task"]?.type == "string")
        #expect(resolve.properties?["task"]?.type == "string")

        let feedback = CapabilitySchemaBuilder.runtimeToolInputSchema(name: "report_skill_feedback")
        #expect(Set(feedback.required ?? []) == ["skill_id", "version", "category", "summary", "evidence"])
        #expect(feedback.properties?["category"]?.enumValues?.contains(.string("poor_discovery")) == true)
        #expect(feedback.properties?["create_issue"]?.type == "boolean")
        #expect(feedback.properties?["evidence"]?.maxLength == 8_000)

        for name in MCPConstants.runtimeToolNames {
            let output = CapabilitySchemaBuilder.runtimeToolOutputSchema(name: name)
            #expect(output.type == "object")
            #expect(output.required?.isEmpty == false)
        }
    }

    @Test func runtimeContextPreservesNestedAndCompatibilityTaskIdentity() throws {
        let nested = try SkillRuntimeToolHandlers.runtimeContext(arguments: [
            "context": .object(["task": .string("MCP-10")]),
        ])
        #expect(nested.task == "MCP-10")

        let compatibility = try SkillRuntimeToolHandlers.runtimeContext(arguments: [
            "context": .object(["task": .string("nested-task")]),
            "task": .string("compatibility-task"),
        ])
        #expect(compatibility.task == "compatibility-task")
    }

    @Test func paginationIsStableAndRejectsWrongContext() throws {
        let values = ["a", "b", "c", "d", "e"]
        let first = try MCPPaginator.page(values, cursor: nil, scope: "tools:release-a", pageSize: 2)
        #expect(first.items == ["a", "b"])
        let second = try MCPPaginator.page(values, cursor: first.nextCursor, scope: "tools:release-a", pageSize: 2)
        #expect(second.items == ["c", "d"])
        let final = try MCPPaginator.page(values, cursor: second.nextCursor, scope: "tools:release-a", pageSize: 2)
        #expect(final.items == ["e"])
        #expect(final.nextCursor == nil)
        #expect(throws: MCPPaginationError.self) {
            try MCPPaginator.page(values, cursor: first.nextCursor, scope: "resources:release-a", pageSize: 2)
        }
        #expect(throws: MCPPaginationError.self) {
            try MCPPaginator.page(values, cursor: "not+a+cursor", scope: "tools:release-a", pageSize: 2)
        }
    }

    @Test func packageResourcePathsAndUrisRejectTraversal() throws {
        #expect(try SkillPackageResourceService.normalize(relativePath: "references/guide.md") == "references/guide.md")
        let uri = SkillPackageResourceService.uri(
            skillId: "swift checks",
            path: "references/guide.md",
            version: "release+abc123"
        )
        #expect(uri == "ctx://skill/swift%20checks/file/references/guide.md?version=release%2Babc123")
        #expect(
            try SkillPackageResourceService.parse(uri: uri) == .init(
                skillId: "swift checks",
                path: "references/guide.md",
                version: "release+abc123"
            )
        )
        #expect(throws: (any Error).self) { try SkillPackageResourceService.normalize(relativePath: "../secret") }
        #expect(throws: (any Error).self) { try SkillPackageResourceService.normalize(relativePath: "%2e%2e/secret") }
        #expect(throws: (any Error).self) { try SkillPackageResourceService.parse(uri: "ctx://skill/swift/file/../secret") }
    }

    @Test func eventPathSegments() {
        let base = McpRoutePath.pathComponents()
        #expect(!(base + ["events"]).isEmpty)
        #expect((base + ["events"]).last == "events")
    }

    @Test func pingPathSegments() {
        let base = McpRoutePath.pathComponents()
        #expect((base + ["ping"]).last == "ping")
    }
}
