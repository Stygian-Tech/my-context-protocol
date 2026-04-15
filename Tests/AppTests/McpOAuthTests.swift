import Fluent
import Foundation
import NIOCore
import Testing
import Vapor
import VaporTesting
@testable import App

@Suite("MCP OAuth", .serialized)
struct McpOAuthTests {
    @Test("Protected resource metadata is 404 when MCP_OAUTH_ENABLED is off")
    func metadataDisabled() async throws {
        try await withMcpOAuthApp(env: [
            "USE_SQLITE": "1",
            "MCP_OAUTH_ENABLED": "0",
            "SAAS_MCP_BASE_DOMAIN": "mcp.oauth.test",
            "FRONTEND_URL": "http://localhost:3000",
            "DATABASE_URL": nil,
            "SUPABASE_DB_URL": nil,
        ]) { app in
            try await app.testing().test(
                .GET,
                "/.well-known/oauth-protected-resource",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: .host, value: "any.mcp.oauth.test")
                },
                afterResponse: { res in
                    #expect(res.status == .notFound)
                }
            )
        }
    }

    @Test("Protected resource metadata returns JSON when MCP_OAUTH_ENABLED is on")
    func metadataEnabled() async throws {
        try await withMcpOAuthApp(env: [
            "USE_SQLITE": "1",
            "MCP_OAUTH_ENABLED": "1",
            "SAAS_MCP_BASE_DOMAIN": "mcp.oauth.test",
            "FRONTEND_URL": "http://localhost:3000",
            "DATABASE_URL": nil,
            "SUPABASE_DB_URL": nil,
        ]) { app in
            try await app.testing().test(
                .GET,
                "/.well-known/oauth-protected-resource",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: .host, value: "any.mcp.oauth.test")
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let ct = res.headers.first(name: .contentType) ?? ""
                    #expect(ct.contains("application/json"))
                }
            )
        }
    }

    @Test("Unauthenticated MCP POST includes WWW-Authenticate when OAuth is enabled")
    func mcpChallengeHeader() async throws {
        try await withMcpOAuthApp(env: [
            "USE_SQLITE": "1",
            "MCP_OAUTH_ENABLED": "1",
            "SAAS_MCP_BASE_DOMAIN": "mcp.oauth.test",
            "FRONTEND_URL": "http://localhost:3000",
            "DATABASE_URL": nil,
            "SUPABASE_DB_URL": nil,
        ]) { app in
            let body = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#
            try await app.testing().test(
                .POST,
                "/mcp",
                body: ByteBuffer(string: body),
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: .host, value: "any.mcp.oauth.test")
                    req.headers.replaceOrAdd(name: .contentType, value: "application/json")
                },
                afterResponse: { res in
                    #expect(res.status == .unauthorized)
                    let www = res.headers.first(name: .wwwAuthenticate) ?? ""
                    #expect(www.contains("resource_metadata="))
                }
            )
        }
    }

    @Test("Client credentials access token can call MCP initialize on tenant host")
    func clientCredentialsMcpInitialize() async throws {
        try await withMcpOAuthApp(env: [
            "USE_SQLITE": "1",
            "MCP_OAUTH_ENABLED": "1",
            "SAAS_MCP_BASE_DOMAIN": "mcp.oauth.test",
            "FRONTEND_URL": "http://localhost:3000",
            "DATABASE_URL": nil,
            "SUPABASE_DB_URL": nil,
        ]) { app in
            let account = Account(githubId: 900_001, login: "oauth-tester", email: "t@example.com")
            try await account.save(on: app.db)
            let project = Project(accountId: account.id!, name: "OAuth Proj", slug: "oauth-proj", subdomain: "oauthsub")
            try await project.save(on: app.db)

            let urisJson = #"["https://client.example/cb"]"#
            let m2m = McpOAuthClient(
                publicClientId: "m2m-test",
                clientSecretHash: McpOAuthCrypto.sha256Hex("supersecret"),
                isConfidential: true,
                redirectUrisJson: urisJson,
                allowedGrants: "authorization_code,client_credentials"
            )
            try await m2m.save(on: app.db)

            let form = "grant_type=client_credentials&client_id=m2m-test&client_secret=supersecret"
            var accessToken = ""
            try await app.testing().test(
                .POST,
                "/token",
                body: ByteBuffer(string: form),
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: .host, value: "oauthsub.mcp.oauth.test")
                    req.headers.replaceOrAdd(
                        name: .contentType,
                        value: "application/x-www-form-urlencoded"
                    )
                },
                afterResponse: { res in
                    #expect(res.status == .ok, "token response status=\(res.status)")
                    let dec = try res.content.decode(OAuthTokenSuccess.self)
                    accessToken = dec.access_token
                }
            )
            #expect(!accessToken.isEmpty)

            let initBody =
                #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{}}}"#
            try await app.testing().test(
                .POST,
                "/mcp",
                body: ByteBuffer(string: initBody),
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: .host, value: "oauthsub.mcp.oauth.test")
                    req.headers.replaceOrAdd(name: .authorization, value: "Bearer \(accessToken)")
                    req.headers.replaceOrAdd(name: .contentType, value: "application/json")
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    #expect(res.headers.first(name: "X-MCP-Catalog-Revision") != nil)
                }
            )
        }
    }
}

private func withMcpOAuthApp(
    env: [String: String?],
    _ run: @Sendable @escaping (Application) async throws -> Void
) async throws {
    try await TestProcessEnvGate.shared.run {
        let prev = AppEnvironment._testOverrideAppEnv
        AppEnvironment._testOverrideAppEnv = "local"
        let (apply, restore) = mcpOAuthTemporaryEnv(env)
        apply()
        defer {
            restore()
            AppEnvironment._testOverrideAppEnv = prev
        }

        let app = try await Application.make(.testing)
        try await configure(app)
        do {
            try await run(app)
        } catch {
            try await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }
}

private func mcpOAuthTemporaryEnv(_ overrides: [String: String?]) -> (() -> Void, () -> Void) {
    var saved: [String: String?] = [:]
    for (key, _) in overrides {
        saved[key] = ProcessInfo.processInfo.environment[key]
    }
    let apply: () -> Void = {
        for (key, val) in overrides {
            if let v = val {
                setenv(key, v, 1)
            } else {
                unsetenv(key)
            }
        }
    }
    let restore: () -> Void = {
        for (key, val) in saved {
            if let v = val {
                setenv(key, v, 1)
            } else {
                unsetenv(key)
            }
        }
    }
    return (apply, restore)
}
