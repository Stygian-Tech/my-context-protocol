import Vapor

/// Lightweight liveness probe for MCP hostnames (no API key or JSON-RPC body).
enum McpPingController {
    private struct PingBody: Content {
        var status = "ok"
        var service = "MyContextProtocol"
    }

    static func handle(req: Request) async throws -> Response {
        if req.method == .HEAD {
            var headers = HTTPHeaders()
            headers.replaceOrAdd(name: .contentType, value: "application/json; charset=utf-8")
            return Response(status: .ok, headers: headers)
        }
        return try await PingBody().encodeResponse(for: req)
    }
}
