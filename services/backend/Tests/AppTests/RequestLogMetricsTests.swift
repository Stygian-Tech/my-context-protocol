import Foundation
import Testing
@testable import App

@Suite("RequestLog metrics")
struct RequestLogMetricsTests {
    @Test func http200WithoutErrorCodeCountsAsSuccess() {
        let log = RequestLog(
            projectId: UUID(),
            method: "tools/list",
            latencyMs: 5,
            status: "200"
        )
        #expect(log.countsAsSuccessfulRequestMetric == true)
    }

    @Test func http404WithJsonRpcErrorCountsAsFailure() {
        let log = RequestLog(
            projectId: UUID(),
            method: "unknown/method",
            latencyMs: 2,
            status: "404",
            errorCode: "-32601",
            errorMessage: "Method not found"
        )
        #expect(log.countsAsSuccessfulRequestMetric == false)
    }

    @Test func http401CountsAsFailure() {
        let log = RequestLog(
            projectId: UUID(),
            method: "tools/list",
            status: "401"
        )
        #expect(log.countsAsSuccessfulRequestMetric == false)
    }
}
