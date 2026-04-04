import Vapor

/// Normalized MCP HTTP path segments from `SAAS_MCP_PATH` (default `/mcp`).
enum McpRoutePath {
    /// Non-empty path segments, e.g. `["mcp"]` or `["v1","mcp"]`.
    static func pathComponents() -> [String] {
        let raw = Environment.get("SAAS_MCP_PATH")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "/mcp"
        var s = raw
        if s.hasPrefix("/") { s.removeFirst() }
        while s.hasSuffix("/"), s.count > 1 { s.removeLast() }
        if s.isEmpty { return ["mcp"] }
        return s.split(separator: "/").map(String.init).filter { !$0.isEmpty }
    }

    /// Registers `POST` for the configured MCP path on `builder` (already grouped with MCP middleware).
    static func registerPost(
        on builder: RoutesBuilder,
        body: HTTPBodyStreamStrategy = .collect(maxSize: ByteCount(value: 2 * 1024 * 1024)),
        handler: @escaping @Sendable (Request) async throws -> Response
    ) {
        let segments = pathComponents()
        guard !segments.isEmpty else {
            builder.on(.POST, "mcp", body: body, use: handler)
            return
        }
        let path: [PathComponent] = segments.map { PathComponent(stringLiteral: $0) }
        if path.count == 1 {
            builder.on(.POST, path[0], body: body, use: handler)
            return
        }
        var group: RoutesBuilder = builder
        for i in 0 ..< (path.count - 1) {
            group = group.grouped(path[i])
        }
        group.on(.POST, path[path.count - 1], body: body, use: handler)
    }

    /// Registers `GET …/events` under the same base path as `registerPost` (SSE for MCP list_changed).
    static func registerGetEvents(on builder: RoutesBuilder, handler: @escaping @Sendable (Request) async throws -> Response) {
        let segments = pathComponents()
        guard !segments.isEmpty else {
            builder.on(.GET, "mcp", "events", use: handler)
            return
        }
        var group: RoutesBuilder = builder
        for seg in segments {
            group = group.grouped(PathComponent(stringLiteral: seg))
        }
        group.on(.GET, "events", use: handler)
    }
}
