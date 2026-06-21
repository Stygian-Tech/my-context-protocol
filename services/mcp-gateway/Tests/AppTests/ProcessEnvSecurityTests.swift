import Foundation
import Testing
import Vapor
import VaporTesting
@testable import App

private func withIsolatedProcessEnv<R: Sendable>(
    _ body: @Sendable () async throws -> R
) async rethrows -> R {
    try await TestProcessEnvGate.run { try await body() }
}

private func withIsolatedProcessEnv<R: Sendable>(
    _ body: @Sendable () async -> R
) async -> R {
    await TestProcessEnvGate.run { await body() }
}

private func withIsolatedProcessEnv<R: Sendable>(
    _ body: @Sendable () throws -> R
) rethrows -> R {
    try TestProcessEnvGate.runSync { try body() }
}

private func withIsolatedProcessEnv<R: Sendable>(
    _ body: @Sendable () -> R
) -> R {
    TestProcessEnvGate.runSync { body() }
}

/// Serialized: mutates process environment and `AppEnvironment` test overrides (unsafe global state).
@Suite("Process env — security and frontend URL", .serialized)
struct ProcessEnvSecurityTests {
    @Test("AppEnvironment deploy kind and bypass flags")
    func deployAndBypass() async throws {
        withIsolatedProcessEnv {
        let prevEnv = AppEnvironment._testOverrideAppEnv
        let prevStrict = AppEnvironment._testOverrideStrict
        defer {
            AppEnvironment._testOverrideAppEnv = prevEnv
            AppEnvironment._testOverrideStrict = prevStrict
        }

        do {
            // Isolate from a process `APP_ENV` (e.g. developer shell or leaked runner state). Overrides
            // are nil here, so deploy kind reads the real environment.
            let (apply, restore) = temporaryEnv(["APP_ENV": nil])
            apply()
            defer { restore() }
            AppEnvironment._testOverrideAppEnv = nil
            AppEnvironment._testOverrideStrict = nil
            #expect(AppEnvironment.deployKind() == .prod)
            #expect(AppEnvironment.strictProGating == true)
            #expect(AppEnvironment.nonProductionBypassesActive == false)
        }

        AppEnvironment._testOverrideStrict = nil
        AppEnvironment._testOverrideAppEnv = "LOCAL"
        #expect(AppEnvironment.deployKind() == .local)
        #expect(AppEnvironment.strictProGating == false)
        #expect(AppEnvironment.nonProductionBypassesActive == true)

        AppEnvironment._testOverrideAppEnv = "dev"
        #expect(AppEnvironment.deployKind() == .dev)
        #expect(AppEnvironment.strictProGating == true)
        #expect(AppEnvironment.nonProductionBypassesActive == false)

        AppEnvironment._testOverrideAppEnv = "prod"
        #expect(AppEnvironment.deployKind() == .prod)
        #expect(AppEnvironment.strictProGating == true)
        #expect(AppEnvironment.nonProductionBypassesActive == false)

        AppEnvironment._testOverrideAppEnv = "local"
        AppEnvironment._testOverrideStrict = true
        #expect(AppEnvironment.strictProGating == true)
        #expect(AppEnvironment.nonProductionBypassesActive == false)
        }
    }

    @Test("McpIpRateLimitMiddleware enforces limit when MCP rate limiting is active")
    func mcpRateLimit() async throws {
        let prevAppEnv = AppEnvironment._testOverrideAppEnv
        defer { AppEnvironment._testOverrideAppEnv = prevAppEnv }
        AppEnvironment._testOverrideAppEnv = "prod"

        try await withApp { app in
            let limiter = McpIpRateLimitMiddleware(limit: 2, windowSeconds: 120)
            let g = app.grouped(limiter)
            g.post("mcp", "rpc") { _ in "ok" }
            try await app.testing().test(.POST, "/mcp/rpc") { res in
                #expect(res.status == .ok)
            }
            try await app.testing().test(.POST, "/mcp/rpc") { res in
                #expect(res.status == .ok)
            }
            try await app.testing().test(.POST, "/mcp/rpc") { res in
                #expect(res.status == .tooManyRequests)
            }
        }
    }

    @Test("normalizedBase prefers FRONTEND_URL and strips slashes")
    func normalizedBase() throws {
        withIsolatedProcessEnv {
            let (apply, restore) = temporaryEnv([
                "FRONTEND_URL": "https://app.test/",
                "CORS_ORIGIN": "https://other.test",
            ])
            apply()
            defer { restore() }
            #expect(AppFrontendURL.normalizedBase() == "https://app.test")
        }
    }

    @Test("allowedOriginBases deduplicates trimmed bases")
    func allowedBasesDedup() throws {
        withIsolatedProcessEnv {
            let (apply, restore) = temporaryEnv([
                "FRONTEND_URL": "https://same/",
                "CORS_ORIGIN": "https://same",
            ])
            apply()
            defer { restore() }
            let bases = AppFrontendURL.allowedOriginBases()
            #expect(bases.count == 1)
            #expect(bases[0] == "https://same")
        }
    }

    @Test("validateReturnTo accepts paths and query-only under configured origin")
    func validateReturnToHappy() async throws {
        try await withIsolatedProcessEnv {
            let (apply, restore) = temporaryEnv([
                "FRONTEND_URL": "https://app.example.com",
            ])
            apply()
            defer { restore() }

            try await withApp { app in
            let req = Request(
                application: app,
                method: .GET,
                url: URI(path: "/"),
                version: .http1_1,
                headers: [:],
                remoteAddress: nil,
                logger: app.logger,
                on: app.eventLoopGroup.next()
            )
            let a = try AppFrontendURL.validateReturnTo("https://app.example.com/oauth/cb", for: req)
            #expect(a == "https://app.example.com/oauth/cb")
            let b = try AppFrontendURL.validateReturnTo("https://app.example.com?state=1", for: req)
            #expect(b == "https://app.example.com?state=1")
            }
        }
    }

    @Test("validateReturnTo rejects disallowed origins when configured")
    func validateReturnToRejects() async throws {
        try await withIsolatedProcessEnv {
            let (apply, restore) = temporaryEnv([
                "FRONTEND_URL": "https://app.example.com",
            ])
            apply()
            defer { restore() }

            try await withApp { app in
            let req = Request(
                application: app,
                method: .GET,
                url: URI(path: "/"),
                version: .http1_1,
                headers: [:],
                remoteAddress: nil,
                logger: app.logger,
                on: app.eventLoopGroup.next()
            )
            #expect(throws: Abort.self) {
                try AppFrontendURL.validateReturnTo("https://evil.com/x", for: req)
            }
            }
        }
    }

    @Test("MCP OAuth resume derives API origin from GitHub login callback before frontend fallback")
    func mcpOAuthResumeDerivesAPIOriginFromGitHubLoginCallback() async throws {
        try await withIsolatedProcessEnv {
            let (apply, restore) = temporaryEnv([
                "FRONTEND_URL": "https://testing.mycontextprotocol.com",
                "CORS_ORIGIN": nil,
                "MCP_OAUTH_API_ORIGIN": nil,
                "WEBHOOK_BASE_URL": nil,
                "GITHUB_OAUTH_REDIRECT_URI": "https://api.testing.mycontextprotocol.com/auth/github/callback",
            ])
            apply()
            defer { restore() }

            let pending = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
            let returnTo = try McpOAuthResumeURL.githubReturnTo(pending: pending)
            #expect(returnTo == "https://api.testing.mycontextprotocol.com/auth/mcp-oauth-resume?pending=11111111-1111-1111-1111-111111111111")

            let start = McpOAuthResumeURL.githubMcpOauthStartLink(pending: pending)
            #expect(start == "https://api.testing.mycontextprotocol.com/auth/github/mcp-oauth-start?pending=11111111-1111-1111-1111-111111111111")

            try await withApp { app in
                let req = Request(
                    application: app,
                    method: .GET,
                    url: URI(path: "/"),
                    version: .http1_1,
                    headers: [:],
                    remoteAddress: nil,
                    logger: app.logger,
                    on: app.eventLoopGroup.next()
                )
                let validated = try AppFrontendURL.validateOAuthReturnTo(returnTo, for: req)
                #expect(validated == returnTo)
            }
        }
    }

    @Test("MCP OAuth resume explicit API origin overrides derived callback origin")
    func mcpOAuthResumeExplicitAPIOriginWins() async throws {
        try withIsolatedProcessEnv {
            let (apply, restore) = temporaryEnv([
                "FRONTEND_URL": "https://testing.mycontextprotocol.com",
                "MCP_OAUTH_API_ORIGIN": "https://api.override.test/",
                "GITHUB_OAUTH_REDIRECT_URI": "https://api.testing.mycontextprotocol.com/auth/github/callback",
            ])
            apply()
            defer { restore() }

            let pending = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
            let returnTo = try McpOAuthResumeURL.githubReturnTo(pending: pending)
            #expect(returnTo == "https://api.override.test/auth/mcp-oauth-resume?pending=22222222-2222-2222-2222-222222222222")
        }
    }

    @Test("validateReturnTo requires configuration in non-local when bases empty")
    func validateReturnToRequiresConfig() async throws {
        try await withIsolatedProcessEnv {
            let (apply, restore) = temporaryEnv([
                "FRONTEND_URL": nil,
                "CORS_ORIGIN": nil,
            ])
            let prev = AppEnvironment._testOverrideAppEnv
            AppEnvironment._testOverrideAppEnv = "prod"
            apply()
            defer {
                restore()
                AppEnvironment._testOverrideAppEnv = prev
            }

            try await withApp { app in
                let req = Request(
                    application: app,
                    method: .GET,
                    url: URI(path: "/"),
                    version: .http1_1,
                    headers: [:],
                    remoteAddress: nil,
                    logger: app.logger,
                    on: app.eventLoopGroup.next()
                )
                #expect(throws: Abort.self) {
                    try AppFrontendURL.validateReturnTo("https://any.test/", for: req)
                }
            }
        }
    }

    @Test("validateReturnTo allows any http(s) URL in local when bases empty")
    func validateReturnToLocalOpen() async throws {
        try await withIsolatedProcessEnv {
            let (apply, restore) = temporaryEnv([
                "FRONTEND_URL": nil,
                "CORS_ORIGIN": nil,
            ])
            let prev = AppEnvironment._testOverrideAppEnv
            AppEnvironment._testOverrideAppEnv = "local"
            apply()
            defer {
                restore()
                AppEnvironment._testOverrideAppEnv = prev
            }

            try await withApp { app in
                let req = Request(
                    application: app,
                    method: .GET,
                    url: URI(path: "/"),
                    version: .http1_1,
                    headers: [:],
                    remoteAddress: nil,
                    logger: app.logger,
                    on: app.eventLoopGroup.next()
                )
                let u = try AppFrontendURL.validateReturnTo("https://any.test/callback", for: req)
                #expect(u == "https://any.test/callback")
            }
        }
    }

    @Test("validateOptionalReturnTo treats empty as nil")
    func optionalReturnTo() async throws {
        try await withIsolatedProcessEnv {
            let (apply, restore) = temporaryEnv([
                "FRONTEND_URL": "https://app.example.com",
            ])
            apply()
            defer { restore() }

            try await withApp { app in
                let req = Request(
                    application: app,
                    method: .GET,
                    url: URI(path: "/"),
                    version: .http1_1,
                    headers: [:],
                    remoteAddress: nil,
                    logger: app.logger,
                    on: app.eventLoopGroup.next()
                )
                let n: String? = try AppFrontendURL.validateOptionalReturnTo(nil, for: req)
                #expect(n == nil)
                let e: String? = try AppFrontendURL.validateOptionalReturnTo("", for: req)
                #expect(e == nil)
                let w: String? = try AppFrontendURL.validateOptionalReturnTo("   ", for: req)
                #expect(w == nil)
            }
        }
    }

    @Test("loginErrorURL encodes query parameter")
    func loginErrorURL() throws {
        withIsolatedProcessEnv {
            let (apply, restore) = temporaryEnv([
                "FRONTEND_URL": "https://app.example.com/",
            ])
            apply()
            defer { restore() }
            let u = AppFrontendURL.loginErrorURL(code: "bad auth")
            #expect(u == "https://app.example.com/login?error=bad%20auth")
        }
    }

    @Test("McpRoutePath respects SAAS_MCP_PATH")
    func mcpRoutePathFromEnv() throws {
        withIsolatedProcessEnv {
            let (apply, restore) = temporaryEnv([
                "SAAS_MCP_PATH": "/v1/tools/mcp/",
            ])
            apply()
            defer { restore() }
            #expect(McpRoutePath.pathComponents() == ["v1", "tools", "mcp"])
        }
    }

    @Test("BrowserOriginValidationMiddleware allows POST with matching Origin")
    func browserOriginAllows() async throws {
        try await withIsolatedProcessEnv {
            let (apply, restore) = temporaryEnv([
                "FRONTEND_URL": "https://app.example.com",
                "CORS_ORIGIN": nil,
            ])
            apply()
            defer { restore() }

            try await withApp { app in
            let g = app.grouped(BrowserOriginValidationMiddleware())
            g.post("action") { _ in "done" }
            try await app.testing().test(
                .POST,
                "/action",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: .origin, value: "https://app.example.com")
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                }
            )
            }
        }
    }

    @Test("BrowserOriginValidationMiddleware rejects POST without Origin when frontend is configured")
    func browserOriginRejects() async throws {
        try await withIsolatedProcessEnv {
            let (apply, restore) = temporaryEnv([
                "FRONTEND_URL": "https://app.example.com",
            ])
            apply()
            defer { restore() }

            try await withApp { app in
            let g = app.grouped(BrowserOriginValidationMiddleware())
            g.post("action") { _ in "done" }
            try await app.testing().test(.POST, "/action") { res in
                #expect(res.status == .forbidden)
            }
            }
        }
    }

    @Test("BrowserOriginValidationMiddleware accepts Referer under allowed base")
    func browserOriginReferer() async throws {
        try await withIsolatedProcessEnv {
            let (apply, restore) = temporaryEnv([
                "FRONTEND_URL": "https://app.example.com",
            ])
            apply()
            defer { restore() }

            try await withApp { app in
            let g = app.grouped(BrowserOriginValidationMiddleware())
            g.post("action") { _ in "done" }
            try await app.testing().test(
                .POST,
                "/action",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: .referer, value: "https://app.example.com/dashboard")
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                }
            )
            }
        }
    }

    @Test("BrowserOriginValidationMiddleware skips webhook paths")
    func browserOriginSkipsWebhooks() async throws {
        try await withIsolatedProcessEnv {
            let (apply, restore) = temporaryEnv([
                "FRONTEND_URL": "https://app.example.com",
            ])
            apply()
            defer { restore() }

            try await withApp { app in
            app.middleware.use(BrowserOriginValidationMiddleware())
            app.post("webhooks", "stripe") { _ in "w" }
            try await app.testing().test(.POST, "/webhooks/stripe") { res in
                #expect(res.status == .ok)
            }
            }
        }
    }

    // MARK: - Internal Pro bypass, crypto, MCP URL (env-dependent)

    @Test("InternalProBypass matches login case-insensitively")
    func internalProLogins() throws {
        withIsolatedProcessEnv {
            let (apply, restore) = temporaryEnv([
                "INTERNAL_PRO_GITHUB_LOGINS": " Admin , user ",
            ])
            apply()
            defer { restore() }
            #expect(InternalProBypass.matches(login: "admin", githubId: 0) == true)
            #expect(InternalProBypass.matches(login: "USER", githubId: 0) == true)
            #expect(InternalProBypass.matches(login: "other", githubId: 0) == false)
        }
    }

    @Test("InternalProBypass matches github id list")
    func internalProIds() throws {
        withIsolatedProcessEnv {
            let (apply, restore) = temporaryEnv([
                "INTERNAL_PRO_GITHUB_IDS": "10, 20 ,bogus,30",
            ])
            apply()
            defer { restore() }
            #expect(InternalProBypass.matches(login: "x", githubId: 20) == true)
            #expect(InternalProBypass.matches(login: "x", githubId: 99) == false)
        }
    }

    @Test("Account hasProEntitlements via internal allowlist in production")
    func accountProInternalAllowlist() throws {
        withIsolatedProcessEnv {
            let (apply, restore) = temporaryEnv([
                "INTERNAL_PRO_GITHUB_LOGINS": "pro-user",
            ])
            let prevEnv = AppEnvironment._testOverrideAppEnv
            let prevStrict = AppEnvironment._testOverrideStrict
            AppEnvironment._testOverrideAppEnv = "prod"
            AppEnvironment._testOverrideStrict = true
            apply()
            defer {
                restore()
                AppEnvironment._testOverrideAppEnv = prevEnv
                AppEnvironment._testOverrideStrict = prevStrict
            }
            let acc = Account(githubId: 100, login: "pro-user")
            #expect(acc.hasProEntitlements == true)
            let other = Account(githubId: 101, login: "free-user")
            #expect(other.hasProEntitlements == false)
        }
    }

    @Test("TokenEncryption round-trip with ENCRYPTION_KEY")
    func tokenEncryptionRoundTrip() throws {
        try withIsolatedProcessEnv {
            let key32 = Data(repeating: 3, count: 32).base64EncodedString()
            let (apply, restore) = temporaryEnv([
                "ENCRYPTION_KEY": key32,
            ])
            apply()
            defer { restore() }
            let enc = try TokenEncryption.encrypt("hello-世界")
            let dec = try TokenEncryption.decrypt(enc)
            #expect(dec == "hello-世界")
        }
    }

    @Test("TokenEncryption errors when key missing or ciphertext invalid")
    func tokenEncryptionErrors() throws {
        withIsolatedProcessEnv {
            let (apply, restore) = temporaryEnv([
                "ENCRYPTION_KEY": nil,
            ])
            apply()
            defer { restore() }
            #expect(throws: TokenEncryptionError.self) {
                _ = try TokenEncryption.encrypt("x")
            }
            let (applyK, restoreK) = temporaryEnv([
                "ENCRYPTION_KEY": Data(repeating: 1, count: 32).base64EncodedString(),
            ])
            applyK()
            defer { restoreK() }
            #expect(throws: TokenEncryptionError.self) {
                _ = try TokenEncryption.decrypt("not-valid-base64!!!")
            }
        }
    }

    @Test("SignedOAuthState GitHub OAuth round-trip")
    func signedOAuthRoundTrip() throws {
        try withIsolatedProcessEnv {
            let key32 = Data(repeating: 5, count: 32).base64EncodedString()
            let (apply, restore) = temporaryEnv([
                "ENCRYPTION_KEY": key32,
            ])
            apply()
            defer { restore() }
            let state = try SignedOAuthState.signGitHubOAuth(returnTo: "https://app.example.com/x")
            let rt = try SignedOAuthState.verifyGitHubOAuth(state: state)
            #expect(rt == "https://app.example.com/x")
        }
    }

    @Test("SignedOAuthState GitHub App install round-trip")
    func signedAppInstallRoundTrip() throws {
        try withIsolatedProcessEnv {
            let key32 = Data(repeating: 8, count: 32).base64EncodedString()
            let (apply, restore) = temporaryEnv([
                "ENCRYPTION_KEY": key32,
            ])
            apply()
            defer { restore() }
            let pid = UUID()
            let state = try SignedOAuthState.signGitHubAppInstall(
                projectId: pid,
                returnTo: "https://app.example.com/r",
                owner: "o",
                repo: "r"
            )
            let out = try SignedOAuthState.verifyGitHubAppInstall(state: state)
            #expect(out.projectId == pid)
            #expect(out.returnTo == "https://app.example.com/r")
            #expect(out.owner == "o")
            #expect(out.repo == "r")
        }
    }

    @Test("SignedOAuthState rejects key when ENCRYPTION_KEY missing")
    func signedOAuthNoKey() throws {
        withIsolatedProcessEnv {
            let (apply, restore) = temporaryEnv([
                "ENCRYPTION_KEY": nil,
            ])
            apply()
            defer { restore() }
            #expect(throws: SignedOAuthState.StateError.self) {
                _ = try SignedOAuthState.signGitHubOAuth(returnTo: "/")
            }
        }
    }

    @Test("SignedOAuthState rejects tampered payload")
    func signedOAuthTamper() throws {
        try withIsolatedProcessEnv {
            let key32 = Data(repeating: 2, count: 32).base64EncodedString()
            let (apply, restore) = temporaryEnv([
                "ENCRYPTION_KEY": key32,
            ])
            apply()
            defer { restore() }
            let state = try SignedOAuthState.signGitHubOAuth(returnTo: "/ok")
            var chars = Array(state)
            if let dot = chars.firstIndex(of: ".") {
                let signatureStart = chars.index(after: dot)
                chars[signatureStart] = chars[signatureStart] == "a" ? "b" : "a"
            }
            let broken = String(chars)
            #expect(throws: SignedOAuthState.StateError.self) {
                _ = try SignedOAuthState.verifyGitHubOAuth(state: broken)
            }
        }
    }

    @Test("SignedOAuthState OAuth verifier rejects app-install payload shape")
    func signedOAuthWrongKind() throws {
        try withIsolatedProcessEnv {
            let key32 = Data(repeating: 4, count: 32).base64EncodedString()
            let (apply, restore) = temporaryEnv([
                "ENCRYPTION_KEY": key32,
            ])
            apply()
            defer { restore() }
            let appState = try SignedOAuthState.signGitHubAppInstall(projectId: UUID(), returnTo: nil)
            #expect(throws: (any Error).self) {
                _ = try SignedOAuthState.verifyGitHubOAuth(state: appState)
            }
        }
    }

    @Test("McpUrlBuilder uses subdomain and env domain")
    func mcpUrlSubdomain() throws {
        withIsolatedProcessEnv {
            let (apply, restore) = temporaryEnv([
                "SAAS_MCP_BASE_DOMAIN": "https://EXAMPLE.dev/",
                "SAAS_MCP_PATH": "/v1/mcp",
                "SAAS_MCP_URL_SCHEME": "HTTP://",
            ])
            apply()
            defer { restore() }
            let p = Project(accountId: UUID(), name: "n", slug: "s", subdomain: "abc123")
            let u = McpUrlBuilder.publicMcpUrl(for: p)
            #expect(u == "http://abc123.example.dev/v1/mcp")
        }
    }

    @Test("McpUrlBuilder prefers verified custom domain")
    func mcpUrlCustomDomain() throws {
        withIsolatedProcessEnv {
            let (apply, restore) = temporaryEnv([
                "SAAS_MCP_PATH": "/mcp",
                "SAAS_MCP_URL_SCHEME": "https",
            ])
            apply()
            defer { restore() }
            let p = Project(
                accountId: UUID(),
                name: "n",
                slug: "s",
                subdomain: "ignored",
                customDomain: "MCP.Custom.COM",
                customDomainVerifiedAt: Date()
            )
            let u = McpUrlBuilder.publicMcpUrl(for: p)
            #expect(u == "https://mcp.custom.com/mcp")
        }
    }

    @Test("McpUrlBuilder returns nil without subdomain or domain config")
    func mcpUrlNil() throws {
        withIsolatedProcessEnv {
            let (apply, restore) = temporaryEnv([
                "SAAS_MCP_BASE_DOMAIN": "",
                "SAAS_MCP_PATH": "/mcp",
            ])
            apply()
            defer { restore() }
            let p = Project(accountId: UUID(), name: "n", slug: "s", subdomain: nil)
            #expect(McpUrlBuilder.publicMcpUrl(for: p) == nil)
        }
    }

    @Test("FlyCertificateService reads runtime certificate config")
    func flyCertificateConfig() throws {
        withIsolatedProcessEnv {
            let (apply, restore) = temporaryEnv([
                "FLY_API_TOKEN": "fly-token",
                "FLY_ACCESS_TOKEN": "",
                "FLY_CERTIFICATE_APP_NAME": "gateway-app",
                "FLY_MCP_GATEWAY_APP": "",
                "FLY_APP_NAME": "",
                "FLY_CERTIFICATE_API_BASE_URL": "https://fly-api.test/",
                "FLY_API_BASE_URL": "",
                "FLY_CERTIFICATE_OWNERSHIP_TXT_VALUE": "app-12qq5w0",
            ])
            apply()
            defer { restore() }
            let config = FlyCertificateService.currentConfig()
            #expect(config?.apiToken == "fly-token")
            #expect(config?.appName == "gateway-app")
            #expect(config?.apiBaseURL == "https://fly-api.test/v1")
            #expect(config?.ownershipTxtValue == "app-12qq5w0")

            let record = FlyCertificateService.ownershipTxtRecord(hostname: "MCP.Example.COM.")
            #expect(record?.name == "_fly-ownership.mcp.example.com")
            #expect(record?.value == "app-12qq5w0")
        }
    }

    @Test("FlyCertificateService parses issued and failed certificate responses")
    func flyCertificateResponseParsing() throws {
        let issued = Data(#"{"certificate":{"configured":true,"client_status":"Ready","issued":{"nodes":[{"type":"rsa"}]}}}"#.utf8)
        let issuedResult = FlyCertificateService.parseResult(from: issued)
        #expect(issuedResult.status == .issued)

        let failed = Data(#"{"certificate":{"configured":false,"validation_errors":[{"message":"CNAME does not point to app"}]}}"#.utf8)
        let failedResult = FlyCertificateService.parseResult(from: failed)
        #expect(failedResult.status == .failed)
        #expect(failedResult.message == "CNAME does not point to app")
    }

    @Test("McpIpRateLimitMiddleware uses X-Forwarded-For when trusted")
    func mcpRateLimitXff() async throws {
        try await withIsolatedProcessEnv {
            let prevAppEnv = AppEnvironment._testOverrideAppEnv
            let (apply, restore) = temporaryEnv([
                "TRUST_X_FORWARDED_FOR": "1",
            ])
            apply()
            defer {
                restore()
                AppEnvironment._testOverrideAppEnv = prevAppEnv
            }
            AppEnvironment._testOverrideAppEnv = "prod"

            try await withApp { app in
            let limiter = McpIpRateLimitMiddleware(limit: 1, windowSeconds: 120)
            let g = app.grouped(limiter)
            g.post("rpc") { _ in "ok" }
            try await app.testing().test(
                .POST,
                "/rpc",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-Forwarded-For", value: "198.51.100.10, 10.0.0.1")
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                }
            )
            try await app.testing().test(
                .POST,
                "/rpc",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-Forwarded-For", value: "198.51.100.10, 10.0.0.1")
                },
                afterResponse: { res in
                    #expect(res.status == .tooManyRequests)
                }
            )
            try await app.testing().test(
                .POST,
                "/rpc",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-Forwarded-For", value: "198.51.100.11, 10.0.0.1")
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                }
            )
            }
        }
    }
}

private func temporaryEnv(_ overrides: [String: String?]) -> (() -> Void, () -> Void) {
    var saved: [String: String?] = [:]
    for (key, _) in overrides {
        saved[key] = ProcessInfo.processInfo.environment[key]
    }
    let apply: () -> Void = {
        for (key, val) in overrides {
            if let v = val {
                setenv(key, v, 1)
            } else {
                setenv(key, "", 1)
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
