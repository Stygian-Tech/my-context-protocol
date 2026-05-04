import Testing
import Vapor
import VaporTesting
@testable import App

@Suite("Security headers middleware")
struct SecurityMiddlewareTests {
    @Test("SecurityHeadersMiddleware adds baseline headers")
    func securityHeaders() async throws {
        try await withApp { app in
            app.middleware.use(SecurityHeadersMiddleware())
            app.get("ping") { _ in "pong" }
            try await app.testing().test(.GET, "/ping") { res in
                #expect(res.status == .ok)
                #expect(res.headers.first(name: "X-Content-Type-Options") == "nosniff")
                #expect(res.headers.first(name: "X-Frame-Options") == "DENY")
                #expect(res.headers.first(name: "Referrer-Policy") == "strict-origin-when-cross-origin")
                #expect(res.headers.first(name: "Permissions-Policy") != nil)
            }
        }
    }
}
