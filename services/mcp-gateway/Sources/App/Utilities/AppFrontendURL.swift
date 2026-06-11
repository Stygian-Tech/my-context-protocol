import Vapor

/// Resolves the public frontend origin for redirects, OAuth `return_to` validation, and billing.
enum AppFrontendURL {
    /// First non-empty `FRONTEND_URL` or `CORS_ORIGIN`, trimmed, no trailing slash.
    static func normalizedBase() -> String? {
        for key in ["FRONTEND_URL", "CORS_ORIGIN"] {
            if let raw = Environment.get(key) {
                let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty {
                    return t.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                }
            }
        }
        return nil
    }

    /// Default browser URL when `return_to` is omitted (e.g. `https://app.example.com/`).
    static func defaultReturnToURL() -> String? {
        guard let base = normalizedBase() else { return nil }
        return base + "/"
    }

    /// Distinct allowed frontend base URLs without trailing slash (e.g. FRONTEND and CORS may differ).
    static func allowedOriginBases() -> [String] {
        var bases: [String] = []
        for key in ["FRONTEND_URL", "CORS_ORIGIN"] {
            if let raw = Environment.get(key) {
                let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty {
                    let b = t.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    if !bases.contains(b) {
                        bases.append(b)
                    }
                }
            }
        }
        return bases
    }

    /// Extra allowed bases for GitHub OAuth `return_to` when resuming MCP OAuth on the API host.
    /// Set `MCP_OAUTH_RESUME_BASE_URLS` to a comma-separated list of origins (no trailing slash), e.g. `https://api.example.com`.
    static func allowedMcpOAuthResumeOriginBases() -> [String] {
        guard let raw = Environment.get("MCP_OAUTH_RESUME_BASE_URLS") else { return [] }
        var out: [String] = []
        for part in raw.split(separator: ",") {
            let t = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { continue }
            let b = t.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !out.contains(b) { out.append(b) }
        }
        return out
    }

    /// Bases allowed for MCP OAuth resume redirects: frontend origins, `MCP_OAUTH_RESUME_BASE_URLS`, and `MCP_OAUTH_API_ORIGIN`.
    /// `MCP_OAUTH_API_ORIGIN` is included automatically because it is already used to *generate* resume URLs —
    /// requiring a separate `MCP_OAUTH_RESUME_BASE_URLS` for the same host is a footgun.
    static func allowedOAuthReturnToBases() -> [String] {
        var bases = allowedOriginBases()
        for b in allowedMcpOAuthResumeOriginBases() where !bases.contains(b) {
            bases.append(b)
        }
        if let raw = Environment.get("MCP_OAUTH_API_ORIGIN")?
            .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            let b = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !bases.contains(b) { bases.append(b) }
        }
        return bases
    }

    /// Like `validateReturnTo`, but also allows `MCP_OAUTH_RESUME_BASE_URLS` entries (for API-hosted resume endpoints).
    static func validateOAuthReturnTo(_ urlString: String, for req: Request) throws -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme,
              scheme == "http" || scheme == "https" else {
            throw Abort(.badRequest, reason: "return_to must be a valid http(s) URL")
        }
        let allowed = allowedOAuthReturnToBases()
        if allowed.isEmpty {
            if AppEnvironment.deployKind() == .local {
                return trimmed
            }
            throw Abort(
                .badRequest,
                reason: "FRONTEND_URL, CORS_ORIGIN, or MCP_OAUTH_RESUME_BASE_URLS must be configured for OAuth return_to validation"
            )
        }
        for origin in allowed {
            if trimmed == origin || trimmed.hasPrefix(origin + "/") || trimmed.hasPrefix(origin + "?") {
                return trimmed
            }
        }
        req.logger.warning("OAuth return_to rejected: does not match allowed origins")
        throw Abort(.badRequest, reason: "return_to origin is not allowed")
    }

    /// Validates `return_to` for OAuth / app-install redirects. When at least one origin is configured,
    /// only URLs under those origins are allowed (open-redirect protection).
    static func validateReturnTo(_ urlString: String, for req: Request) throws -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme,
              scheme == "http" || scheme == "https" else {
            throw Abort(.badRequest, reason: "return_to must be a valid http(s) URL")
        }
        let allowed = allowedOriginBases()
        if allowed.isEmpty {
            if AppEnvironment.deployKind() == .local {
                return trimmed
            }
            throw Abort(
                .badRequest,
                reason: "FRONTEND_URL or CORS_ORIGIN must be configured for return_to validation"
            )
        }
        for origin in allowed {
            if trimmed == origin || trimmed.hasPrefix(origin + "/") || trimmed.hasPrefix(origin + "?") {
                return trimmed
            }
        }
        req.logger.warning("Redirect return_to rejected: does not match FRONTEND_URL or CORS_ORIGIN")
        throw Abort(.badRequest, reason: "return_to origin is not allowed")
    }

    /// Optional `return_to` for GitHub App install: empty string means “use default frontend URL”.
    static func validateOptionalReturnTo(_ urlString: String?, for req: Request) throws -> String? {
        guard let s = urlString?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else {
            return nil
        }
        return try validateReturnTo(s, for: req)
    }

    /// Rejects open redirects: path only, must start with `/`, not `//`, no control characters.
    static func validateRelativeBrowserPath(_ raw: String, label: String = "redirect") throws -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("/") else {
            throw Abort(.badRequest, reason: "\(label) must be a relative path starting with /")
        }
        guard !t.hasPrefix("//") else {
            throw Abort(.badRequest, reason: "Invalid \(label)")
        }
        if t.contains("\r") || t.contains("\n") || t.contains("\0") {
            throw Abort(.badRequest, reason: "Invalid \(label)")
        }
        guard t.count <= 4096 else {
            throw Abort(.badRequest, reason: "\(label) is too long")
        }
        return t
    }

    /// Stripe checkout success/cancel paths (relative only).
    static func validateCheckoutRelativePath(_ raw: String?, default defaultPath: String) throws -> String {
        let trimmedDefault = defaultPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let r = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty else {
            return try validateRelativeBrowserPath(trimmedDefault, label: "billing_path")
        }
        return try validateRelativeBrowserPath(r, label: "billing_path")
    }

    /// `/login?error=...` on the configured frontend, for OAuth failures when `return_to` is unknown.
    static func loginErrorURL(code: String) -> String? {
        guard let base = normalizedBase() else { return nil }
        let enc = code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? code
        return "\(base)/login?error=\(enc)"
    }
}
