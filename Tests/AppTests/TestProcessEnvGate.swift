import Foundation

/// Serializes tests that mutate `ProcessInfo.processInfo.environment` so parallel Swift Testing
/// workers do not clobber each other (e.g. `MCP_OAUTH_ENABLED`).
///
/// `NSLock` is unavailable from asynchronous contexts; an actor provides mutual exclusion for
/// `async` test bodies without blocking an executor.
actor TestProcessEnvGate {
    static let shared = TestProcessEnvGate()

    func run<R: Sendable>(
        _ body: @Sendable () async throws -> R
    ) async rethrows -> R {
        try await body()
    }
}
