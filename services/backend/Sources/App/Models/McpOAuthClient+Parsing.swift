import Foundation
import Vapor

extension McpOAuthClient {
    func parsedRedirectUris() throws -> [String] {
        try JSONDecoder().decode([String].self, from: Data(redirectUrisJson.utf8))
    }

    func allowsGrant(_ name: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return allowedGrants
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains(n)
    }

    var isActive: Bool { status == "active" }
}
