import Foundation
import Testing
@testable import App

@Suite("Capability usage aggregation")
struct CapabilityUsageAggregationTests {
    @Test func groupsByKindAndKeyAndCountsSuccess() {
        let pid = UUID()
        let okTool = RequestLog(
            projectId: pid,
            method: "tools/call",
            latencyMs: 1,
            status: "200",
            mcpCapabilityKind: "tool",
            mcpCapabilityKey: "alpha"
        )
        let failTool = RequestLog(
            projectId: pid,
            method: "tools/call",
            latencyMs: 2,
            status: "404",
            errorCode: "-32601",
            mcpCapabilityKind: "tool",
            mcpCapabilityKey: "alpha"
        )
        let okResource = RequestLog(
            projectId: pid,
            method: "resources/read",
            status: "200",
            mcpCapabilityKind: "resource",
            mcpCapabilityKey: "ctx://skill/foo"
        )

        let rows = CapabilityUsageAggregation.breakdown(from: [okTool, failTool, okResource])
        #expect(rows.count == 2)
        let alpha = rows.first { $0.kind == "tool" && $0.key == "alpha" }
        #expect(alpha?.invocations_last_7d == 2)
        #expect(alpha?.successful_last_7d == 1)
        let res = rows.first { $0.kind == "resource" }
        #expect(res?.invocations_last_7d == 1)
        #expect(res?.successful_last_7d == 1)
    }

    @Test func ignoresUntaggedLogs() {
        let pid = UUID()
        let plain = RequestLog(projectId: pid, method: "tools/list", status: "200")
        #expect(CapabilityUsageAggregation.breakdown(from: [plain]).isEmpty)
    }
}
