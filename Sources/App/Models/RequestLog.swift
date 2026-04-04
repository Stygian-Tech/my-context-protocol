import Fluent
import Vapor

final class RequestLog: Model, Content {
    static let schema = "request_logs"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "project_id")
    var project: Project

    @OptionalParent(key: "release_id")
    var release: Release?

    @Timestamp(key: "timestamp", on: .create)
    var timestamp: Date?

    @OptionalField(key: "client_id")
    var clientId: String?

    @Field(key: "method")
    var method: String

    @OptionalField(key: "latency_ms")
    var latencyMs: Int?

    @Field(key: "status")
    var status: String

    @OptionalField(key: "error_code")
    var errorCode: String?

    @OptionalField(key: "error_message")
    var errorMessage: String?

    init() {}

    init(
        id: UUID? = nil,
        projectId: UUID,
        releaseId: UUID? = nil,
        clientId: String? = nil,
        method: String,
        latencyMs: Int? = nil,
        status: String,
        errorCode: String? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.$project.id = projectId
        self.$release.id = releaseId
        self.clientId = clientId
        self.method = method
        self.latencyMs = latencyMs
        self.status = status
        self.errorCode = errorCode
        self.errorMessage = errorMessage
    }
}

extension RequestLog: @unchecked Sendable {}

extension RequestLog {
    /// For dashboards: HTTP 2xx/3xx **and** no JSON-RPC error. MCP returns HTTP 200 with `error` for RPC failures
    /// (`-32601` method not found, etc.); those rows set `error_code` and must not count as successes on charts.
    var countsAsSuccessfulRequestMetric: Bool {
        guard let code = Int(status), (200 ..< 400).contains(code) else { return false }
        if let ec = errorCode?.trimmingCharacters(in: .whitespacesAndNewlines), !ec.isEmpty {
            return false
        }
        return true
    }
}
