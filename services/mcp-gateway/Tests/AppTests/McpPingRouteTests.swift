import Foundation
import Testing
import Vapor
import VaporTesting
@testable import App

@Suite("MCP /ping route", .serialized)
struct McpPingRouteTests {
    @Test func getPingReturnsOkJsonWithoutCredentials() async throws {
        try await TestProcessEnvGate.run {
            let prev = AppEnvironment._testOverrideAppEnv
            AppEnvironment._testOverrideAppEnv = "local"
            let (apply, restore) = Self.pingTestEnv()
            apply()
            defer {
                restore()
                AppEnvironment._testOverrideAppEnv = prev
            }

            let app = try await Application.make(.testing)
            try await configure(app)
            do {
                try await app.testing().test(.GET, "/mcp/ping", afterResponse: { res in
                    #expect(res.status == .ok)
                    let text = res.body.string
                    #expect(text.contains("\"status\":\"ok\""))
                    #expect(text.contains("MyContextProtocol"))
                })

                try await app.testing().test(.HEAD, "/mcp/ping", afterResponse: { res in
                    #expect(res.status == .ok)
                    #expect(res.body.readableBytes == 0)
                })

                try await app.testing().test(
                    .POST,
                    "/mcp/ping",
                    body: ByteBuffer(string: ""),
                    beforeRequest: { req in
                        req.headers.replaceOrAdd(name: .contentType, value: "application/json")
                    },
                    afterResponse: { res in
                        #expect(res.status == .ok)
                        #expect(res.body.string.contains("\"status\":\"ok\""))
                    }
                )
            } catch {
                try await app.asyncShutdown()
                throw error
            }
            try await app.asyncShutdown()
        }
    }

    private static func pingTestEnv() -> (() -> Void, () -> Void) {
        var saved: [String: String?] = [:]
        let keys = [
            "USE_SQLITE", "USE_MEMORY_SESSIONS", "MCP_OAUTH_ENABLED", "FRONTEND_URL",
            "DATABASE_URL", "SUPABASE_DB_URL",
        ]
        for k in keys {
            saved[k] = ProcessInfo.processInfo.environment[k]
        }
        let apply: () -> Void = {
            setenv("USE_SQLITE", "1", 1)
            setenv("USE_MEMORY_SESSIONS", "1", 1)
            setenv("MCP_OAUTH_ENABLED", "0", 1)
            setenv("FRONTEND_URL", "http://localhost:3000", 1)
            setenv("DATABASE_URL", "", 1)
            setenv("SUPABASE_DB_URL", "", 1)
        }
        let restore: () -> Void = {
            for (k, v) in saved {
                if let val = v {
                    setenv(k, val, 1)
                } else {
                    unsetenv(k)
                }
            }
        }
        return (apply, restore)
    }
}
