import Foundation
import Vapor

/// Monotonic catalog revision per project and optional SSE fan-out for MCP list_changed notifications.
final class McpCatalogNotifications: @unchecked Sendable {
    private let lock = NSLock()
    private var revision: [UUID: UInt64] = [:]
    private var subscribers: [UUID: [UUID: AsyncStream<String>.Continuation]] = [:]

    func currentRevision(for projectId: UUID) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return revision[projectId] ?? 0
    }

    /// Bump after any change that alters tools/resources/prompts for the active MCP catalog.
    func bumpCatalog(for projectId: UUID) {
        let continuations: [AsyncStream<String>.Continuation]
        lock.lock()
        let next = (revision[projectId] ?? 0) + 1
        revision[projectId] = next
        let subs = subscribers[projectId] ?? [:]
        continuations = Array(subs.values)
        lock.unlock()

        let payloads = [
            #"{"jsonrpc":"2.0","method":"notifications/tools/list_changed"}"#,
            #"{"jsonrpc":"2.0","method":"notifications/resources/list_changed"}"#,
            #"{"jsonrpc":"2.0","method":"notifications/prompts/list_changed"}"#,
        ]
        for cont in continuations {
            for p in payloads {
                cont.yield("data: \(p)\n\n")
            }
        }
    }

    func registerSubscriber(projectId: UUID, id: UUID, continuation: AsyncStream<String>.Continuation) {
        lock.lock()
        defer { lock.unlock() }
        if subscribers[projectId] == nil {
            subscribers[projectId] = [:]
        }
        subscribers[projectId]![id] = continuation
    }

    func removeSubscriber(projectId: UUID, id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        subscribers[projectId]?[id] = nil
        if subscribers[projectId]?.isEmpty == true {
            subscribers[projectId] = nil
        }
    }
}

extension Application {
    struct McpCatalogNotificationsKey: StorageKey {
        typealias Value = McpCatalogNotifications
    }

    var mcpCatalogNotifications: McpCatalogNotifications {
        if let existing = storage[McpCatalogNotificationsKey.self] {
            return existing
        }
        let n = McpCatalogNotifications()
        storage[McpCatalogNotificationsKey.self] = n
        return n
    }
}

extension Request {
    /// Adds `X-MCP-Catalog-Revision` for MCP JSON-RPC responses.
    func attachMcpCatalogRevisionHeader(to response: Response) {
        guard let project = storage[ProjectKey.self], let pid = project.id else { return }
        let rev = application.mcpCatalogNotifications.currentRevision(for: pid)
        response.headers.replaceOrAdd(name: "X-MCP-Catalog-Revision", value: String(rev))
    }
}
