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

    /// Distinct allowed origins (e.g. FRONTEND and CORS may differ).
    private static func allowedOriginBases() -> [String] {
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
            // Local dev: no FRONTEND_URL / CORS_ORIGIN — allow any http(s) URL.
            return trimmed
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

    /// `/login?error=...` on the configured frontend, for OAuth failures when `return_to` is unknown.
    static func loginErrorURL(code: String) -> String? {
        guard let base = normalizedBase() else { return nil }
        let enc = code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? code
        return "\(base)/login?error=\(enc)"
    }
}
