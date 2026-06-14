import Fluent
import Foundation
import NIOCore
import Crypto
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
                    let metadata = try res.content.decode(OAuthProtectedResourceMetadata.self)
                    #expect(metadata.resource == "http://any.mcp.oauth.test/mcp")
                    #expect(metadata.authorization_servers == ["http://any.mcp.oauth.test"])
                }
            )
        }
    }

    @Test("Authorization server metadata advertises Claude-compatible public clients")
    func authorizationServerMetadataSupportsPublicClients() async throws {
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
                "/.well-known/oauth-authorization-server",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: .host, value: "any.mcp.oauth.test")
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let metadata = try res.content.decode(OAuthAuthorizationServerMetadata.self)
                    #expect(metadata.issuer == "http://any.mcp.oauth.test")
                    #expect(metadata.registration_endpoint == "http://any.mcp.oauth.test/register")
                    #expect(metadata.code_challenge_methods_supported.contains("S256"))
                    #expect(metadata.grant_types_supported.contains("refresh_token"))
                    #expect(metadata.token_endpoint_auth_methods_supported.contains("client_secret_basic"))
                    #expect(metadata.token_endpoint_auth_methods_supported.contains("none"))
                    #expect(metadata.scopes_supported == [McpOAuthConstants.defaultScope])
                }
            )
        }
    }

    @Test("Tenant root on MCP host returns OAuth discovery challenge")
    func tenantRootReturnsOAuthChallenge() async throws {
        try await withMcpOAuthApp(env: [
            "USE_SQLITE": "1",
            "MCP_OAUTH_ENABLED": "1",
            "SAAS_MCP_BASE_DOMAIN": "mcp.oauth.test",
            "FRONTEND_URL": "http://localhost:3000",
            "DATABASE_URL": nil,
            "SUPABASE_DB_URL": nil,
        ]) { app in
            let account = Account(githubId: 900_008, login: "root-challenge", email: "root-challenge@example.com")
            try await account.save(on: app.db)
            let project = Project(accountId: account.id!, name: "Root Challenge", slug: "root-challenge", subdomain: "rootchallenge")
            try await project.save(on: app.db)

            try await app.testing().test(
                .GET,
                "/",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: .host, value: "rootchallenge.mcp.oauth.test")
                },
                afterResponse: { res in
                    #expect(res.status == .unauthorized)
                    let www = res.headers.first(name: .wwwAuthenticate) ?? ""
                    #expect(www.contains(#"resource_metadata="http://rootchallenge.mcp.oauth.test/.well-known/oauth-protected-resource/mcp""#))
                    #expect(www.contains(#"scope="mcp:invoke""#))
                    #expect(res.body.string.contains("http://rootchallenge.mcp.oauth.test/mcp"))
                }
            )
        }
    }

    @Test("Tenant host resolution accepts scheme-prefixed SAAS_MCP_BASE_DOMAIN")
    func tenantResolutionNormalizesBaseDomainScheme() async throws {
        try await withMcpOAuthApp(env: [
            "USE_SQLITE": "1",
            "MCP_OAUTH_ENABLED": "1",
            "SAAS_MCP_BASE_DOMAIN": "https://mcp.oauth.test",
            "FRONTEND_URL": "http://localhost:3000",
            "DATABASE_URL": nil,
            "SUPABASE_DB_URL": nil,
        ]) { app in
            let account = Account(githubId: 900_009, login: "scheme-base", email: "scheme-base@example.com")
            try await account.save(on: app.db)
            let project = Project(accountId: account.id!, name: "Scheme Base", slug: "scheme-base", subdomain: "schemebase")
            try await project.save(on: app.db)

            try await app.testing().test(
                .GET,
                "/",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: .host, value: "schemebase.mcp.oauth.test")
                    req.headers.replaceOrAdd(name: "X-Forwarded-Proto", value: "https")
                },
                afterResponse: { res in
                    #expect(res.status == .unauthorized)
                    let www = res.headers.first(name: .wwwAuthenticate) ?? ""
                    #expect(www.contains(#"resource_metadata="https://schemebase.mcp.oauth.test/.well-known/oauth-protected-resource/mcp""#))
                }
            )

            let body = """
            {"redirect_uris":["https://claude.ai/api/mcp/auth_callback"],"client_name":"Claude","grant_types":["authorization_code"],"response_types":["code"],"token_endpoint_auth_method":"none"}
            """
            try await app.testing().test(
                .POST,
                "/register",
                body: ByteBuffer(string: body),
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: .host, value: "schemebase.mcp.oauth.test")
                    req.headers.replaceOrAdd(name: .contentType, value: "application/json")
                    req.headers.replaceOrAdd(name: "X-Forwarded-Proto", value: "https")
                },
                afterResponse: { res in
                    #expect(res.status == .created, "registration status=\(res.status) body=\(res.body.string)")
                    let registration = try JSONDecoder().decode(TestRegistrationResponse.self, from: Data(buffer: res.body))
                    #expect(!registration.client_id.isEmpty)
                    #expect(registration.client_secret == nil)
                }
            )
        }
    }

    @Test("Authorization server metadata supports path-suffixed discovery")
    func authorizationServerMetadataSupportsPathSuffix() async throws {
        try await withMcpOAuthApp(env: [
            "USE_SQLITE": "1",
            "MCP_OAUTH_ENABLED": "1",
            "SAAS_MCP_BASE_DOMAIN": "https://mcp.oauth.test",
            "FRONTEND_URL": "http://localhost:3000",
            "DATABASE_URL": nil,
            "SUPABASE_DB_URL": nil,
        ]) { app in
            let account = Account(githubId: 900_010, login: "auth-suffix", email: "auth-suffix@example.com")
            try await account.save(on: app.db)
            let project = Project(accountId: account.id!, name: "Auth Suffix", slug: "auth-suffix", subdomain: "authsuffix")
            try await project.save(on: app.db)

            try await app.testing().test(
                .GET,
                "/.well-known/oauth-authorization-server/mcp",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: .host, value: "authsuffix.mcp.oauth.test")
                    req.headers.replaceOrAdd(name: "X-Forwarded-Proto", value: "https")
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let metadata = try res.content.decode(OAuthAuthorizationServerMetadata.self)
                    #expect(metadata.issuer == "https://authsuffix.mcp.oauth.test")
                    #expect(metadata.registration_endpoint == "https://authsuffix.mcp.oauth.test/register")
                }
            )
        }
    }

    @Test("App root remains plain text on non-MCP host")
    func appRootRemainsPlainText() async throws {
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
                "/",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: .host, value: "api.example.test")
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    #expect(res.body.string == "MyContextProtocol")
                    #expect(res.headers.first(name: .wwwAuthenticate) == nil)
                }
            )
        }
    }

    @Test("Protected resource metadata supports path-suffixed discovery on verified custom domains")
    func metadataPathSuffixForVerifiedCustomDomain() async throws {
        try await withMcpOAuthApp(env: [
            "USE_SQLITE": "1",
            "MCP_OAUTH_ENABLED": "1",
            "REQUIRE_MCP_TENANT_HOST": "1",
            "SAAS_MCP_BASE_DOMAIN": "mcp.oauth.test",
            "FRONTEND_URL": "http://localhost:3000",
            "DATABASE_URL": nil,
            "SUPABASE_DB_URL": nil,
        ]) { app in
            let account = Account(githubId: 900_002, login: "custom-domain-oauth", email: "custom@example.com")
            try await account.save(on: app.db)
            let project = Project(
                accountId: account.id!,
                name: "Custom Domain OAuth",
                slug: "custom-domain-oauth",
                customDomain: "mcp.custom.example",
                customDomainVerifiedAt: Date()
            )
            try await project.save(on: app.db)

            try await app.testing().test(
                .GET,
                "/.well-known/oauth-protected-resource/mcp",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: .host, value: "mcp.custom.example")
                    req.headers.replaceOrAdd(name: "X-Forwarded-Proto", value: "https")
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let metadata = try res.content.decode(OAuthProtectedResourceMetadata.self)
                    #expect(metadata.resource == "https://mcp.custom.example/mcp")
                    #expect(metadata.authorization_servers == ["https://mcp.custom.example"])
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
                    #expect(www.contains(#"resource_metadata="http://any.mcp.oauth.test/.well-known/oauth-protected-resource/mcp""#))
                    #expect(www.contains(#"scope="mcp:invoke""#))
                }
            )
        }
    }

    @Test("Unauthenticated Streamable HTTP GET includes WWW-Authenticate when OAuth is enabled")
    func mcpGetChallengeHeader() async throws {
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
                "/mcp",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: .host, value: "any.mcp.oauth.test")
                    req.headers.replaceOrAdd(name: .accept, value: "text/event-stream")
                },
                afterResponse: { res in
                    #expect(res.status == .unauthorized)
                    let www = res.headers.first(name: .wwwAuthenticate) ?? ""
                    #expect(www.contains(#"resource_metadata="http://any.mcp.oauth.test/.well-known/oauth-protected-resource/mcp""#))
                    #expect(www.contains(#"scope="mcp:invoke""#))
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

    @Test("Claude public DCR returns no client_secret for token_endpoint_auth_method none")
    func publicClientRegistrationOmitsSecret() async throws {
        try await withMcpOAuthApp(env: [
            "USE_SQLITE": "1",
            "MCP_OAUTH_ENABLED": "1",
            "SAAS_MCP_BASE_DOMAIN": "mcp.oauth.test",
            "FRONTEND_URL": "http://localhost:3000",
            "DATABASE_URL": nil,
            "SUPABASE_DB_URL": nil,
        ]) { app in
            let account = Account(githubId: 900_003, login: "claude-dcr", email: "claude-dcr@example.com")
            try await account.save(on: app.db)
            let project = Project(accountId: account.id!, name: "Claude DCR", slug: "claude-dcr", subdomain: "claudedcr")
            try await project.save(on: app.db)

            let body = """
            {"redirect_uris":["http://localhost:49152/callback"],"client_name":"Claude","grant_types":["authorization_code"],"response_types":["code"],"token_endpoint_auth_method":"none"}
            """
            try await app.testing().test(
                .POST,
                "/register",
                body: ByteBuffer(string: body),
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: .host, value: "claudedcr.mcp.oauth.test")
                    req.headers.replaceOrAdd(name: .contentType, value: "application/json")
                },
                afterResponse: { res in
                    #expect(res.status == .created)
                    let registration = try JSONDecoder().decode(TestRegistrationResponse.self, from: Data(buffer: res.body))
                    #expect(!registration.client_id.isEmpty)
                    #expect(registration.client_secret == nil)
                    #expect(registration.token_endpoint_auth_method == "none")
                }
            )
        }
    }

    @Test("Claude DCR accepts refresh_token grant registration request")
    func claudeRegistrationAllowsRefreshTokenGrantRequest() async throws {
        try await withMcpOAuthApp(env: [
            "USE_SQLITE": "1",
            "MCP_OAUTH_ENABLED": "1",
            "SAAS_MCP_BASE_DOMAIN": "mcp.oauth.test",
            "FRONTEND_URL": "http://localhost:3000",
            "DATABASE_URL": nil,
            "SUPABASE_DB_URL": nil,
        ]) { app in
            let account = Account(githubId: 900_011, login: "claude-refresh-dcr", email: "claude-refresh-dcr@example.com")
            try await account.save(on: app.db)
            let project = Project(accountId: account.id!, name: "Claude Refresh DCR", slug: "claude-refresh-dcr", subdomain: "clauderefresh")
            try await project.save(on: app.db)

            let body = """
            {"redirect_uris":["https://claude.ai/api/mcp/auth_callback"],"client_name":"Claude","grant_types":["authorization_code","refresh_token"],"response_types":["code"],"token_endpoint_auth_method":"client_secret_post"}
            """
            try await app.testing().test(
                .POST,
                "/register",
                body: ByteBuffer(string: body),
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: .host, value: "clauderefresh.mcp.oauth.test")
                    req.headers.replaceOrAdd(name: .contentType, value: "application/json")
                },
                afterResponse: { res in
                    #expect(res.status == .created, "registration status=\(res.status) body=\(res.body.string)")
                    let registration = try JSONDecoder().decode(TestRegistrationResponse.self, from: Data(buffer: res.body))
                    #expect(registration.token_endpoint_auth_method == "client_secret_post")
                    #expect(registration.grant_types == ["authorization_code", "refresh_token"])
                    #expect(registration.client_secret?.isEmpty == false)
                }
            )
        }
    }

    @Test("Confidential DCR supports client_secret_basic and token endpoint Basic auth")
    func confidentialClientRegistrationSupportsBasicAuth() async throws {
        try await withMcpOAuthApp(env: [
            "USE_SQLITE": "1",
            "MCP_OAUTH_ENABLED": "1",
            "SAAS_MCP_BASE_DOMAIN": "mcp.oauth.test",
            "FRONTEND_URL": "http://localhost:3000",
            "DATABASE_URL": nil,
            "SUPABASE_DB_URL": nil,
        ]) { app in
            let account = Account(githubId: 900_007, login: "claude-basic", email: "claude-basic@example.com")
            try await account.save(on: app.db)
            let project = Project(accountId: account.id!, name: "Claude Basic", slug: "claude-basic", subdomain: "claudebasic")
            try await project.save(on: app.db)

            let body = """
            {"redirect_uris":["https://claude.ai/api/mcp/auth_callback"],"client_name":"Claude","grant_types":["client_credentials"],"token_endpoint_auth_method":"client_secret_basic"}
            """
            var registration: TestRegistrationResponse?
            try await app.testing().test(
                .POST,
                "/register",
                body: ByteBuffer(string: body),
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: .host, value: "claudebasic.mcp.oauth.test")
                    req.headers.replaceOrAdd(name: .contentType, value: "application/json")
                },
                afterResponse: { res in
                    #expect(res.status == .created)
                    registration = try JSONDecoder().decode(TestRegistrationResponse.self, from: Data(buffer: res.body))
                    #expect(registration?.token_endpoint_auth_method == "client_secret_basic")
                    #expect(registration?.client_secret?.isEmpty == false)
                }
            )
            let client = try #require(registration)
            let secret = try #require(client.client_secret)
            let credentials = Data("\(client.client_id):\(secret)".utf8).base64EncodedString()
            let tokenForm = "grant_type=client_credentials&client_id=\(urlEncode(client.client_id))"

            try await app.testing().test(
                .POST,
                "/token",
                body: ByteBuffer(string: tokenForm),
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: .host, value: "claudebasic.mcp.oauth.test")
                    req.headers.replaceOrAdd(name: .contentType, value: "application/x-www-form-urlencoded")
                    req.headers.replaceOrAdd(name: .authorization, value: "Basic \(credentials)")
                },
                afterResponse: { res in
                    #expect(res.status == .ok, "token response status=\(res.status) body=\(res.body.string)")
                    let token = try res.content.decode(OAuthTokenSuccess.self)
                    #expect(token.token_type == "Bearer")
                    #expect(token.scope == McpOAuthConstants.defaultScope)
                }
            )
        }
    }

    @Test("Claude authorization code flow accepts localhost loopback and resource parameter")
    func claudeAuthorizationCodeFlowLocalhost() async throws {
        try await runClaudeAuthorizationCodeFlow(redirectUri: "http://localhost:49152/callback")
    }

    @Test("Claude authorization code flow accepts 127.0.0.1 loopback and resource parameter")
    func claudeAuthorizationCodeFlowLoopbackIP() async throws {
        try await runClaudeAuthorizationCodeFlow(redirectUri: "http://127.0.0.1:49153/callback")
    }

    @Test("Claude authorization code flow supports confidential client_secret_post registration")
    func claudeAuthorizationCodeFlowConfidentialClientSecretPost() async throws {
        try await runClaudeAuthorizationCodeFlow(
            redirectUri: "https://claude.ai/api/mcp/auth_callback",
            registrationGrantTypes: ["authorization_code", "refresh_token"],
            tokenEndpointAuthMethod: "client_secret_post"
        )
    }

    @Test("Authorize rejects resource for a different MCP host")
    func authorizeRejectsMismatchedResource() async throws {
        try await withMcpOAuthApp(env: [
            "USE_SQLITE": "1",
            "MCP_OAUTH_ENABLED": "1",
            "SAAS_MCP_BASE_DOMAIN": "mcp.oauth.test",
            "FRONTEND_URL": "http://localhost:3000",
            "DATABASE_URL": nil,
            "SUPABASE_DB_URL": nil,
        ]) { app in
            let account = Account(githubId: 900_006, login: "claude-resource", email: "claude-resource@example.com")
            try await account.save(on: app.db)
            let project = Project(accountId: account.id!, name: "Claude Resource", slug: "claude-resource", subdomain: "clauderesource")
            try await project.save(on: app.db)
            let client = try await registerPublicClient(app, host: "clauderesource.mcp.oauth.test", redirectUri: "http://localhost:49154/callback")
            let verifier = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
            let challenge = pkceChallenge(verifier)
            let authorizePath = "/authorize?response_type=code&client_id=\(urlEncode(client.client_id))&redirect_uri=\(urlEncode("http://localhost:49154/callback"))&state=state-resource&scope=\(urlEncode(McpOAuthConstants.defaultScope))&code_challenge=\(urlEncode(challenge))&code_challenge_method=S256&resource=\(urlEncode("http://other.mcp.oauth.test/mcp"))"

            try await app.testing().test(
                .GET,
                authorizePath,
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: .host, value: "clauderesource.mcp.oauth.test")
                },
                afterResponse: { res in
                    #expect(res.status.code >= 300 && res.status.code < 400)
                    let location = res.headers.first(name: .location) ?? ""
                    #expect(location.contains("error=invalid_target"))
                }
            )
        }
    }
}

private struct TestRegistrationResponse: Decodable {
    var client_id: String
    var client_secret: String?
    var redirect_uris: [String]
    var grant_types: [String]
    var response_types: [String]
    var token_endpoint_auth_method: String
}

private func runClaudeAuthorizationCodeFlow(
    redirectUri: String,
    registrationGrantTypes: [String] = ["authorization_code"],
    tokenEndpointAuthMethod: String = "none"
) async throws {
    try await withMcpOAuthApp(env: [
        "USE_SQLITE": "1",
        "MCP_OAUTH_ENABLED": "1",
        "SAAS_MCP_BASE_DOMAIN": "mcp.oauth.test",
        "FRONTEND_URL": "http://localhost:3000",
        "DATABASE_URL": nil,
        "SUPABASE_DB_URL": nil,
    ]) { app in
        let account = Account(githubId: Int64(900_004 + redirectUri.count), login: "claude-flow", email: "claude-flow@example.com")
        try await account.save(on: app.db)
        let project = Project(accountId: account.id!, name: "Claude Flow", slug: "claude-flow", subdomain: "claudeflow")
        try await project.save(on: app.db)

        let host = "claudeflow.mcp.oauth.test"
        let resource = "http://\(host)/mcp"
        let client = try await registerClient(
            app,
            host: host,
            redirectUri: redirectUri,
            grantTypes: registrationGrantTypes,
            tokenEndpointAuthMethod: tokenEndpointAuthMethod
        )
        if tokenEndpointAuthMethod == "none" {
            #expect(client.client_secret == nil)
        } else {
            #expect(client.client_secret?.isEmpty == false)
        }

        let verifier = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
        let challenge = pkceChallenge(verifier)
        let state = "claude-state"
        let authorizePath = "/authorize?response_type=code&client_id=\(urlEncode(client.client_id))&redirect_uri=\(urlEncode(redirectUri))&state=\(urlEncode(state))&scope=\(urlEncode(McpOAuthConstants.defaultScope))&code_challenge=\(urlEncode(challenge))&code_challenge_method=S256&resource=\(urlEncode(resource))"

        var pendingId: UUID?
        try await app.testing().test(
            .GET,
            authorizePath,
            beforeRequest: { req in
                req.headers.replaceOrAdd(name: .host, value: host)
            },
            afterResponse: { res in
                #expect(res.status.code >= 300 && res.status.code < 400)
                let location = res.headers.first(name: .location) ?? ""
                #expect(location.hasPrefix("/auth/github/mcp-oauth-start?pending="))
                pendingId = pendingFromGithubStartLocation(location)
            }
        )
        let pending = try #require(pendingId)
        let handoffToken = try await OAuthHandoffService.issue(accountId: account.id!, on: app.db)

        var consentToken = ""
        try await app.testing().test(
            .GET,
            "/oauth/consent?pending=\(pending.uuidString)&auth_token=\(urlEncode(handoffToken))",
            beforeRequest: { req in
                req.headers.replaceOrAdd(name: .host, value: host)
            },
            afterResponse: { res in
                #expect(res.status == .ok)
                consentToken = try extractHiddenInput("consent_token", from: res.body.string)
                #expect(!consentToken.isEmpty)
            }
        )

        var authorizationCode = ""
        let consentForm = formEncode([
            "pending": pending.uuidString,
            "decision": "approve",
            "consent_token": consentToken,
        ])
        try await app.testing().test(
            .POST,
            "/oauth/consent",
            body: ByteBuffer(string: consentForm),
            beforeRequest: { req in
                req.headers.replaceOrAdd(name: .host, value: host)
                req.headers.replaceOrAdd(name: .contentType, value: "application/x-www-form-urlencoded")
            },
            afterResponse: { res in
                #expect(res.status.code >= 300 && res.status.code < 400)
                let location = res.headers.first(name: .location) ?? ""
                #expect(location.hasPrefix(redirectUri))
                #expect(location.contains("state=\(state)"))
                authorizationCode = try queryValue("code", in: location)
                #expect(!authorizationCode.isEmpty)
            }
        )

        var tokenFields = [
            "grant_type": "authorization_code",
            "code": authorizationCode,
            "redirect_uri": redirectUri,
            "client_id": client.client_id,
            "code_verifier": verifier,
            "resource": resource,
        ]
        if let clientSecret = client.client_secret {
            tokenFields["client_secret"] = clientSecret
        }
        let tokenForm = formEncode(tokenFields)
        var accessToken = ""
        try await app.testing().test(
            .POST,
            "/token",
            body: ByteBuffer(string: tokenForm),
            beforeRequest: { req in
                req.headers.replaceOrAdd(name: .host, value: host)
                req.headers.replaceOrAdd(name: .contentType, value: "application/x-www-form-urlencoded")
            },
            afterResponse: { res in
                #expect(res.status == .ok, "token response status=\(res.status) body=\(res.body.string)")
                let token = try res.content.decode(OAuthTokenSuccess.self)
                accessToken = token.access_token
                #expect(token.token_type == "Bearer")
                #expect(token.scope == McpOAuthConstants.defaultScope)
            }
        )

        let initBody =
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{}}}"#
        try await app.testing().test(
            .POST,
            "/mcp",
            body: ByteBuffer(string: initBody),
            beforeRequest: { req in
                req.headers.replaceOrAdd(name: .host, value: host)
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

private func registerPublicClient(_ app: Application, host: String, redirectUri: String) async throws -> TestRegistrationResponse {
    try await registerClient(app, host: host, redirectUri: redirectUri, grantTypes: ["authorization_code"], tokenEndpointAuthMethod: "none")
}

private func registerClient(
    _ app: Application,
    host: String,
    redirectUri: String,
    grantTypes: [String],
    tokenEndpointAuthMethod: String
) async throws -> TestRegistrationResponse {
    let grantsJson = grantTypes.map { #""\#($0)""# }.joined(separator: ",")
    let body = """
    {"redirect_uris":["\(redirectUri)"],"client_name":"Claude","grant_types":[\(grantsJson)],"response_types":["code"],"token_endpoint_auth_method":"\(tokenEndpointAuthMethod)"}
    """
    var registration: TestRegistrationResponse?
    try await app.testing().test(
        .POST,
        "/register",
        body: ByteBuffer(string: body),
        beforeRequest: { req in
            req.headers.replaceOrAdd(name: .host, value: host)
            req.headers.replaceOrAdd(name: .contentType, value: "application/json")
        },
        afterResponse: { res in
            #expect(res.status == .created, "registration status=\(res.status) body=\(res.body.string)")
            registration = try JSONDecoder().decode(TestRegistrationResponse.self, from: Data(buffer: res.body))
        }
    )
    return try #require(registration)
}

private func pkceChallenge(_ verifier: String) -> String {
    let hash = SHA256.hash(data: Data(verifier.utf8))
    return Data(hash).base64URLEncodedString
}

private func formEncode(_ values: [String: String]) -> String {
    values.map { "\($0.key)=\(urlEncode($0.value))" }.joined(separator: "&")
}

private func urlEncode(_ value: String) -> String {
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: ":/?#[]@!$&'()*+,;=")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}

private func pendingFromGithubStartLocation(_ location: String) -> UUID? {
    guard let components = URLComponents(string: "http://test\(location)"),
          let raw = components.queryItems?.first(where: { $0.name == "pending" })?.value else {
        return nil
    }
    return UUID(uuidString: raw)
}

private func queryValue(_ name: String, in url: String) throws -> String {
    let components = try #require(URLComponents(string: url))
    return try #require(components.queryItems?.first(where: { $0.name == name })?.value)
}

private func extractHiddenInput(_ name: String, from html: String) throws -> String {
    let marker = #"name="\#(name)" value=""#
    guard let markerRange = html.range(of: marker) else {
        throw Abort(.internalServerError, reason: "Missing hidden input \(name)")
    }
    let start = markerRange.upperBound
    guard let end = html[start...].firstIndex(of: "\"") else {
        throw Abort(.internalServerError, reason: "Malformed hidden input \(name)")
    }
    return String(html[start..<end])
}

private func withMcpOAuthApp(
    env: [String: String?],
    _ run: @Sendable @escaping (Application) async throws -> Void
) async throws {
    try await TestProcessEnvGate.run {
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
