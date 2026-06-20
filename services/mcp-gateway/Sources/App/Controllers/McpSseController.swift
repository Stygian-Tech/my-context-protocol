import NIOCore
import Vapor

/// Server-Sent Events stream for MCP `list_changed` notifications (same auth as POST MCP).
enum McpSseController {
    static func handle(req: Request) async throws -> Response {
        guard let project = req.storage[ProjectKey.self], let pid = project.id else {
            throw Abort(.unauthorized)
        }
        let app = req.application
        let subId = UUID()
        let stream = AsyncStream<String> { continuation in
            app.mcpCatalogNotifications.registerSubscriber(projectId: pid, id: subId, continuation: continuation)
            continuation.onTermination = { @Sendable _ in
                app.mcpCatalogNotifications.removeSubscriber(projectId: pid, id: subId)
            }
        }

        var headers = HTTPHeaders()
        headers.replaceOrAdd(name: .contentType, value: "text/event-stream; charset=utf-8")
        headers.replaceOrAdd(name: .cacheControl, value: "no-cache, no-transform")
        headers.replaceOrAdd(name: .connection, value: "keep-alive")

        return Response(
            status: .ok,
            headers: headers,
            body: .init(asyncStream: { writer in
                var ping = ByteBuffer()
                ping.writeString(":connected\n\n")
                try await writer.write(.buffer(ping))
                for await chunk in stream {
                    var buf = ByteBuffer()
                    buf.writeString(chunk)
                    try await writer.write(.buffer(buf))
                }
                try await writer.write(.end)
            })
        )
    }
}
