import Foundation
import Vapor

/// Tracks `resources/subscribe` URIs per API key (in-memory; best-effort for HTTP MCP).
final class McpResourceSubscriptions: @unchecked Sendable {
    private let lock = NSLock()
    private var byKey: [UUID: Set<String>] = [:]

    func subscribe(apiKeyId: UUID, uri: String) {
        lock.lock()
        defer { lock.unlock() }
        byKey[apiKeyId, default: []].insert(uri)
    }

    func unsubscribe(apiKeyId: UUID, uri: String) {
        lock.lock()
        defer { lock.unlock() }
        byKey[apiKeyId]?.remove(uri)
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
