import Vapor

enum McpOAuthResumeURL {
    /// URL the GitHub OAuth callback returns to, which establishes the session and resumes MCP consent on the tenant host.
    static func githubReturnTo(pending: UUID) throws -> String {
        let path = "/auth/mcp-oauth-resume?pending=\(pending.uuidString)"
        if let base = try preferredAPIOrigin() {
            return "\(base)\(path)"
        }
        guard let fe = AppFrontendURL.normalizedBase() else {
            throw Abort(
                .internalServerError,
                reason: "FRONTEND_URL or CORS_ORIGIN must be set (or set MCP_OAUTH_API_ORIGIN) for MCP OAuth resume"
            )
        }
        return "\(fe)\(path)"
    }

    /// Absolute URL for starting GitHub login to resume a pending MCP authorization (may be API or relative path).
    static func githubMcpOauthStartLink(pending: UUID) -> String {
        let path = "/auth/github/mcp-oauth-start?pending=\(pending.uuidString)"
        if let base = try? preferredAPIOrigin() {
            return "\(base)\(path)"
        }
        return path
    }

    private static func preferredAPIOrigin() throws -> String? {
        if let raw = Environment.get("MCP_OAUTH_API_ORIGIN")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            return raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        guard let redirectURI = try? GitHubOAuthLoginConfig.redirectURI() else {
            return nil
        }
        guard let components = URLComponents(string: redirectURI),
              let scheme = components.scheme,
              let host = components.host,
              components.path == GitHubOAuthLoginConfig.callbackPath else {
            return nil
        }
        if host == "localhost" || host == "127.0.0.1" || host == "::1" {
            return nil
        }
        var origin = "\(scheme)://\(host)"
        if let port = components.port {
            origin += ":\(port)"
        }
        return origin
    }
}
