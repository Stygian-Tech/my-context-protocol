import Vapor

/// Validates `Origin` / `Referer` for browser-initiated mutating requests (CSRF defense in depth for cookie auth).
struct BrowserOriginValidationMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        if Self.shouldSkip(path: request.url.path, method: request.method) {
            request.logger.devTrace("origin_check skipped path=\(request.url.path) method=\(request.method)")
            return try await next.respond(to: request)
        }
        guard [.POST, .PUT, .PATCH, .DELETE].contains(request.method) else {
            return try await next.respond(to: request)
        }

        let bases = AppFrontendURL.allowedOriginBases()
        if bases.isEmpty, AppEnvironment.deployKind() == .local {
            request.logger.devTrace("origin_check bypass local_no_frontend_url path=\(request.url.path)")
            return try await next.respond(to: request)
        }
        guard !bases.isEmpty else {
            request.logger.warning("Origin check: FRONTEND_URL / CORS_ORIGIN not set; rejecting state-changing request")
            return jsonError(status: .forbidden, message: "Server configuration error")
        }

        if let origin = request.headers.first(name: .origin), Self.originMatches(origin, bases: bases) {
            request.logger.devTrace("origin_check ok via Origin path=\(request.url.path)")
            return try await next.respond(to: request)
        }
        if let referer = request.headers.first(name: .referer), Self.refererMatches(referer, bases: bases) {
            request.logger.devTrace("origin_check ok via Referer path=\(request.url.path)")
            return try await next.respond(to: request)
        }

        request.logger.warning("Origin validation failed for \(request.method) \(request.url.path)")
        return jsonError(status: .forbidden, message: "Invalid origin")
    }

    private static func shouldSkip(path: String, method: HTTPMethod) -> Bool {
        if path.hasPrefix("/webhooks/") { return true }
        let mcpPath = "/" + McpRoutePath.pathComponents().joined(separator: "/")
        if path == mcpPath { return true }
        if path == mcpPath + "/ping" { return true }
        if path.hasPrefix("/auth/github") { return true }
        if path == "/auth/github/callback" || path == "/auth/github/app/callback" { return true }
        if path == "/auth/confirm" { return true }
        // OAuth 2.0 token endpoint (tenant host): non-browser clients often omit Origin.
        if path == "/token" { return true }
        return false
    }

    private static func originMatches(_ origin: String, bases: [String]) -> Bool {
        let o = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        return bases.contains { b in
            o.caseInsensitiveCompare(b) == .orderedSame
        }
    }

    private static func refererMatches(_ referer: String, bases: [String]) -> Bool {
        let r = referer.trimmingCharacters(in: .whitespacesAndNewlines)
        return bases.contains { b in
            r.hasPrefix(b + "/") || r.hasPrefix(b + "?") || r.caseInsensitiveCompare(b) == .orderedSame
        }
    }
}
