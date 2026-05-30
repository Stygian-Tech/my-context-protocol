import Foundation
import Vapor

/// Tracks `resources/subscribe` URIs per subscriber (API key id or OAuth access-token row id; in-memory; best-effort for HTTP MCP).
final class McpResourceSubscriptions: @unchecked Sendable {
    private let lock = NSLock()
    private var bySubscriber: [UUID: Set<String>] = [:]

    func subscribe(subscriberId: UUID, uri: String) {
        lock.lock()
        defer { lock.unlock() }
        bySubscriber[subscriberId, default: []].insert(uri)
    }

    func unsubscribe(subscriberId: UUID, uri: String) {
        lock.lock()
        defer { lock.unlock() }
        bySubscriber[subscriberId]?.remove(uri)
    }
}

extension Application {
    struct McpResourceSubscriptionsKey: StorageKey {
        typealias Value = McpResourceSubscriptions
    }

    var mcpResourceSubscriptions: McpResourceSubscriptions {
        if let existing = storage[McpResourceSubscriptionsKey.self] {
            return existing
        }
        let s = McpResourceSubscriptions()
        storage[McpResourceSubscriptionsKey.self] = s
        return s
    }
}
