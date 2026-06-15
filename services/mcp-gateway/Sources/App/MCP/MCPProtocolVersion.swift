import Foundation

/// Negotiates MCP `protocolVersion` for the initialize handshake.
enum MCPProtocolVersion {
    /// Versions this server is tested against (newest first).
    static let supportedDescending = ["2025-06-18", "2024-11-05"]

    static func negotiated(requested: String?) -> String {
        let trimmed = requested?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty, supportedDescending.contains(trimmed) {
            return trimmed
        }
        return "2024-11-05"
    }
}
