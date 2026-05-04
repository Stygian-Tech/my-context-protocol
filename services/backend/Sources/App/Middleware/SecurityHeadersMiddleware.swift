import Vapor

/// Baseline security headers for HTTP responses.
struct SecurityHeadersMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let response = try await next.respond(to: request)
        response.headers.replaceOrAdd(name: .xContentTypeOptions, value: "nosniff")
        response.headers.replaceOrAdd(name: .xFrameOptions, value: "DENY")
        response.headers.replaceOrAdd(name: "Referrer-Policy", value: "strict-origin-when-cross-origin")
        response.headers.replaceOrAdd(
            name: "Permissions-Policy",
            value: "camera=(), microphone=(), geolocation=(), payment=()"
        )
        return response
    }
}
