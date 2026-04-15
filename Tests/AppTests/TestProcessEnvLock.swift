import Foundation

/// Serializes tests that mutate `ProcessInfo.processInfo.environment` so parallel Swift Testing
/// workers do not clobber each other (e.g. `MCP_OAUTH_ENABLED`).
enum TestProcessEnvLock {
    static let shared = NSLock()
}
