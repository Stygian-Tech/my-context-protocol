import Foundation

/// Serializes test bodies that mutate the libc / `ProcessInfo` environment (`setenv` / `unsetenv`)
/// so parallel Swift Testing workers do not clobber each other's `Environment.get` reads.
///
/// **Why not an actor?** An `actor` serializes method entry, but `await` inside `run` suspends the
/// actor, so another task can start a second `run` while the first test is mid-flight.
enum TestProcessEnvGate {
    private static let lock = NSLock()

    /// Holds the lock for the entire async region, including awaits.
    static func run<R: Sendable>(
        _ body: @Sendable () async throws -> R
    ) async rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try await body()
    }

    static func runSync<R: Sendable>(
        _ body: @Sendable () throws -> R
    ) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
