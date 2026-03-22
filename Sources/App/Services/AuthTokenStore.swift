import Foundation

/// In-memory store for one-time OAuth handoff tokens. Used when redirect-based
/// session cookies fail (e.g. Cursor/Electron). Frontend exchanges token via
/// GET /auth/confirm?token= to establish session via fetch (same context as API calls).
enum AuthTokenStore {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var tokens: [String: (accountId: String, expiresAt: Date)] = [:]
    private static let ttl: TimeInterval = 300 // 5 minutes

    static func put(_ token: String, accountId: String) {
        lock.lock()
        defer { lock.unlock() }
        tokens[token] = (accountId, Date().addingTimeInterval(ttl))
    }

    static func consume(_ token: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = tokens[token], entry.expiresAt > Date() else {
            tokens[token] = nil
            return nil
        }
        tokens[token] = nil
        return entry.accountId
    }
}
