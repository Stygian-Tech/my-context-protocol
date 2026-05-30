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

    /// Opaque client reference. API key auth stores `apikey:<uuid>` (not the display name); list endpoints resolve to the current name. OAuth uses `oauth:…` labels. Older rows may still hold legacy string labels.
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

    /// When set with `mcp_capability_key`, identifies a concrete MCP catalog invocation (`tool` / `resource` / `prompt`).
    @OptionalField(key: "mcp_capability_kind")
    var mcpCapabilityKind: String?

    /// Tool name, resource URI, or prompt name — matches MCP `tools/call`, `resources/read`, or `prompts/get` targets.
    @OptionalField(key: "mcp_capability_key")
    var mcpCapabilityKey: String?

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
        errorMessage: String? = nil,
        mcpCapabilityKind: String? = nil,
        mcpCapabilityKey: String? = nil
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
        self.mcpCapabilityKind = mcpCapabilityKind
        self.mcpCapabilityKey = mcpCapabilityKey
    }
}

extension RequestLog: @unchecked Sendable {}

extension RequestLog {
    /// For dashboards: HTTP 2xx/3xx **and** no JSON-RPC error in the logged row.
    /// MCP failures use non-success HTTP status and still set `error_code` / `error_message` when applicable.
    var countsAsSuccessfulRequestMetric: Bool {
        guard let code = Int(status), (200 ..< 400).contains(code) else { return false }
        if let ec = errorCode?.trimmingCharacters(in: .whitespacesAndNewlines), !ec.isEmpty {
            return false
        }
        return true
    }
}
