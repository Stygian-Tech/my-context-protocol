import Foundation
import Vapor

enum McpOAuthConstants {
    static let defaultScope = "mcp:invoke"
    static let accessTokenPrefix = "mcp_oat_"
    static let authorizationCodePrefix = "mcp_oac_"

    static var accessTokenTTLSeconds: TimeInterval {
        if let raw = Environment.get("MCP_OAUTH_ACCESS_TOKEN_TTL_SECONDS"),
           let v = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)), v > 0 {
            return TimeInterval(v)
        }
        return 3600
    }

    static var authorizationCodeTTLSeconds: TimeInterval {
        if let raw = Environment.get("MCP_OAUTH_CODE_TTL_SECONDS"),
           let v = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)), v > 0 {
            return TimeInterval(v)
        }
        return 600
    }

    static var pendingAuthorizationTTLSeconds: TimeInterval {
        if let raw = Environment.get("MCP_OAUTH_PENDING_TTL_SECONDS"),
           let v = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)), v > 0 {
            return TimeInterval(v)
        }
        return 900
    }
}
