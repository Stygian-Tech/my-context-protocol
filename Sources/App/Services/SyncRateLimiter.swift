import Foundation
import Vapor

/// In-memory sliding-window limiter for manual sync (per account + project).
final class SyncRateLimiter: @unchecked Sendable {
    private let lock = NSLock()
    private var windows: [String: Window] = [:]

    private struct Window {
        var periodStart: Date
        var count: Int
    }

    /// Returns false if the request exceeds the limit for this window.
    func allow(
        accountId: UUID,
        projectId: UUID,
        maxRequests: Int,
        windowSeconds: TimeInterval
    ) -> Bool {
        let key = "\(accountId.uuidString):\(projectId.uuidString)"
        let now = Date()
        lock.lock()
        defer { lock.unlock() }
        var w = windows[key] ?? Window(periodStart: now, count: 0)
        if now.timeIntervalSince(w.periodStart) >= windowSeconds {
            w = Window(periodStart: now, count: 0)
        }
        if w.count >= maxRequests {
            return false
        }
        w.count += 1
        windows[key] = w
        return true
    }
}

struct SyncRateLimiterKey: StorageKey {
    typealias Value = SyncRateLimiter
}

extension Application {
    var syncRateLimiter: SyncRateLimiter {
        if let existing = storage[SyncRateLimiterKey.self] {
            return existing
        }
        let limiter = SyncRateLimiter()
        storage[SyncRateLimiterKey.self] = limiter
        return limiter
    }
}
