import Crypto
import Foundation
import NIOCore
import Testing
import Vapor
import VaporTesting
@testable import App

@Suite("Security finding mitigations", .serialized)
struct SecurityFindingMitigationTests {
    @Test("Stripe downgrade suspends all but earliest free project")
    func stripeDowngradeSuspendsExcessProjects() async throws {
        try await withHardeningApp(appEnv: "prod", env: [
            "USE_SQLITE": "1",
            "USE_MEMORY_SESSIONS": "1",
            "SAAS_MCP_BASE_DOMAIN": "mcp.test",
            "STRIPE_WEBHOOK_SECRET": "test_stripe_secret",
            "FREE_PROJECT_LIMIT": "1",
            "DATABASE_URL": nil,
            "SUPABASE_DB_URL": nil,
        ]) { app in
            let account = Account(githubId: 910_001, login: "downgrade-user", email: "downgrade@example.com")
            account.stripeCustomerId = "cus_downgrade"
            account.stripeSubscriptionId = "sub_downgrade"
            account.subscriptionStatus = "active"
            try await account.save(on: app.db)

            let first = Project(accountId: account.id!, name: "First", slug: "first", subdomain: "first")
            let second = Project(accountId: account.id!, name: "Second", slug: "second", subdomain: "second")
            try await first.save(on: app.db)
            try await second.save(on: app.db)

            let payload = stripeSubscriptionPayload(type: "customer.subscription.updated", subscriptionId: "sub_downgrade", customerId: "cus_downgrade", status: "canceled")
            try await postStripeWebhook(app: app, payload: payload, secret: "test_stripe_secret")

            let updatedFirst = try #require(try await Project.find(first.id, on: app.db))
            let updatedSecond = try #require(try await Project.find(second.id, on: app.db))
            #expect(updatedFirst.suspendedAt == nil)
            #expect(updatedSecond.suspendedAt != nil)
        }
    }

    @Test("Stripe delete suspends all but earliest free project")
    func stripeDeleteSuspendsExcessProjects() async throws {
        try await withHardeningApp(appEnv: "prod", env: [
            "USE_SQLITE": "1",
            "USE_MEMORY_SESSIONS": "1",
            "SAAS_MCP_BASE_DOMAIN": "mcp.test",
            "STRIPE_WEBHOOK_SECRET": "test_stripe_secret",
            "FREE_PROJECT_LIMIT": "1",
            "DATABASE_URL": nil,
            "SUPABASE_DB_URL": nil,
        ]) { app in
            let account = Account(githubId: 910_002, login: "delete-user", email: "delete@example.com")
            account.stripeCustomerId = "cus_delete"
            account.stripeSubscriptionId = "sub_delete"
            account.subscriptionStatus = "active"
            try await account.save(on: app.db)

            let first = Project(accountId: account.id!, name: "First", slug: "first", subdomain: "deletefirst")
            let second = Project(accountId: account.id!, name: "Second", slug: "second", subdomain: "deletesecond")
            try await first.save(on: app.db)
            try await second.save(on: app.db)

            let payload = stripeSubscriptionPayload(type: "customer.subscription.deleted", subscriptionId: "sub_delete", customerId: "cus_delete", status: nil)
            try await postStripeWebhook(app: app, payload: payload, secret: "test_stripe_secret")

            let updatedFirst = try #require(try await Project.find(first.id, on: app.db))
            let updatedSecond = try #require(try await Project.find(second.id, on: app.db))
            #expect(updatedFirst.suspendedAt == nil)
            #expect(updatedSecond.suspendedAt != nil)
        }
    }

    @Test("Stripe reactivation unsuspends projects")
    func stripeReactivationUnsuspendsProjects() async throws {
        try await withHardeningApp(appEnv: "prod", env: [
            "USE_SQLITE": "1",
            "USE_MEMORY_SESSIONS": "1",
            "SAAS_MCP_BASE_DOMAIN": "mcp.test",
            "STRIPE_WEBHOOK_SECRET": "test_stripe_secret",
            "FREE_PROJECT_LIMIT": "1",
            "DATABASE_URL": nil,
            "SUPABASE_DB_URL": nil,
        ]) { app in
            let account = Account(githubId: 910_003, login: "reactivate-user", email: "reactivate@example.com")
            account.stripeCustomerId = "cus_reactivate"
            account.stripeSubscriptionId = "sub_reactivate"
            account.subscriptionStatus = "canceled"
            try await account.save(on: app.db)

            let first = Project(accountId: account.id!, name: "First", slug: "first", subdomain: "reactfirst")
            let second = Project(accountId: account.id!, name: "Second", slug: "second", subdomain: "reactsecond")
            first.suspendedAt = Date()
            second.suspendedAt = Date()
            try await first.save(on: app.db)
            try await second.save(on: app.db)

            let payload = stripeSubscriptionPayload(type: "customer.subscription.updated", subscriptionId: "sub_reactivate", customerId: "cus_reactivate", status: "active")
            try await postStripeWebhook(app: app, payload: payload, secret: "test_stripe_secret")

            let updatedFirst = try #require(try await Project.find(first.id, on: app.db))
            let updatedSecond = try #require(try await Project.find(second.id, on: app.db))
            #expect(updatedFirst.suspendedAt == nil)
            #expect(updatedSecond.suspendedAt == nil)
        }
    }

    @Test("Verified custom domain requires current Pro entitlement to route")
    func verifiedCustomDomainRequiresCurrentProEntitlement() async throws {
        try await withHardeningApp(appEnv: "prod", env: [
            "USE_SQLITE": "1",
            "USE_MEMORY_SESSIONS": "1",
            "SAAS_MCP_BASE_DOMAIN": "mcp.test",
            "DATABASE_URL": nil,
            "SUPABASE_DB_URL": nil,
        ]) { app in
            let account = Account(githubId: 910_004, login: "custom-free", email: "custom-free@example.com")
            account.subscriptionStatus = "canceled"
            try await account.save(on: app.db)
            let project = Project(
                accountId: account.id!,
                name: "Custom Free",
                slug: "custom-free",
                subdomain: "customfree",
                customDomain: "mcp.free.example",
                customDomainVerifiedAt: Date()
            )
            try await project.save(on: app.db)

            try await app.testing().test(
                .GET,
                "/",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: .host, value: "mcp.free.example")
                },
                afterResponse: { res in
                    #expect(res.status == .paymentRequired)
                    #expect(res.body.string.contains("Custom domain routing requires an active Pro entitlement"))
                }
            )
        }
    }

    @Test("Verified custom domain routes for Pro account")
    func verifiedCustomDomainRoutesForProAccount() async throws {
        try await withHardeningApp(appEnv: "prod", env: [
            "USE_SQLITE": "1",
            "USE_MEMORY_SESSIONS": "1",
            "MCP_OAUTH_ENABLED": "0",
            "SAAS_MCP_BASE_DOMAIN": "mcp.test",
            "DATABASE_URL": nil,
            "SUPABASE_DB_URL": nil,
        ]) { app in
            let account = Account(githubId: 910_005, login: "custom-pro", email: "custom-pro@example.com")
            account.subscriptionStatus = "active"
            try await account.save(on: app.db)
            let project = Project(
                accountId: account.id!,
                name: "Custom Pro",
                slug: "custom-pro",
                subdomain: "custompro",
                customDomain: "mcp.pro.example",
                customDomainVerifiedAt: Date()
            )
            try await project.save(on: app.db)

            try await app.testing().test(
                .GET,
                "/",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: .host, value: "mcp.pro.example")
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    #expect(res.body.string == "MyContextProtocol")
                }
            )
        }
    }

    @Test("Fly certificate config validates API base URL and app name")
    func flyCertificateConfigValidation() async throws {
        await TestProcessEnvGate.run {
            let (apply, restore) = hardeningTemporaryEnv([
                "FLY_API_TOKEN": "fly_secret",
                "FLY_CERTIFICATE_APP_NAME": "valid-app-1",
                "FLY_CERTIFICATE_API_BASE_URL": "https://api.machines.dev/",
                "FLY_CERTIFICATE_OWNERSHIP_TXT_VALUE": "app-12qq5w0",
            ])
            apply()
            defer { restore() }
            #expect(FlyCertificateService.Config.fromEnvironment()?.apiBaseURL == "https://api.machines.dev/v1")
            #expect(FlyCertificateService.Config.fromEnvironment()?.ownershipTxtValue == "app-12qq5w0")
        }

        await TestProcessEnvGate.run {
            let (apply, restore) = hardeningTemporaryEnv([
                "FLY_API_TOKEN": "fly_secret",
                "FLY_CERTIFICATE_APP_NAME": "valid-app-1",
                "FLY_CERTIFICATE_API_BASE_URL": "https://api.machines.dev/v1/",
            ])
            apply()
            defer { restore() }
            #expect(FlyCertificateService.Config.fromEnvironment()?.apiBaseURL == "https://api.machines.dev/v1")
        }

        await TestProcessEnvGate.run {
            let (apply, restore) = hardeningTemporaryEnv([
                "FLY_API_TOKEN": "fly_secret",
                "FLY_CERTIFICATE_APP_NAME": "bad/app",
                "FLY_CERTIFICATE_API_BASE_URL": "https://api.machines.dev",
            ])
            apply()
            defer { restore() }
            #expect(FlyCertificateService.Config.fromEnvironment() == nil)
        }

        await TestProcessEnvGate.run {
            let (apply, restore) = hardeningTemporaryEnv([
                "FLY_API_TOKEN": "fly_secret",
                "FLY_CERTIFICATE_APP_NAME": "valid-app-1",
                "FLY_CERTIFICATE_API_BASE_URL": "file:///tmp/fly",
            ])
            apply()
            defer { restore() }
            #expect(FlyCertificateService.Config.fromEnvironment() == nil)
        }

        await TestProcessEnvGate.run {
            let (apply, restore) = hardeningTemporaryEnv([
                "FLY_API_TOKEN": "fly_secret",
                "FLY_CERTIFICATE_APP_NAME": "valid-app-1",
                "FLY_CERTIFICATE_API_BASE_URL": "https://api.machines.dev",
                "FLY_CERTIFICATE_OWNERSHIP_TXT_VALUE": "bad token with spaces",
            ])
            apply()
            defer { restore() }
            #expect(FlyCertificateService.Config.fromEnvironment() == nil)
        }
    }

    @Test("Fly certificate path escaping is segment strict")
    func flyCertificatePathEscapingIsSegmentStrict() {
        #expect(FlyCertificateService.pathSegmentEscape("app/name?#") == "app%2Fname%3F%23")
        #expect(FlyCertificateService.pathSegmentEscape("mcp.example.com") == "mcp.example.com")
    }

    @Test("Fly certificate HTTP errors redact response bodies")
    func flyCertificateHTTPErrorDescriptionRedactsBodies() {
        let error = FlyCertificateError.http(status: .badRequest, body: "secret-token-in-body")
        #expect(String(describing: error) == "HTTP 400")
        #expect(!String(describing: error).contains("secret-token-in-body"))
    }

    @Test("Internal TLS ask requires secret and allocated project subdomain")
    func internalTlsAskRequiresSecretAndAllocatedProjectSubdomain() async throws {
        try await withHardeningApp(appEnv: "prod", env: [
            "USE_SQLITE": "1",
            "USE_MEMORY_SESSIONS": "1",
            "SAAS_MCP_BASE_DOMAIN": "mcp.test",
            "INTERNAL_TLS_ASK_SECRET": "tls-ask-secret",
            "DATABASE_URL": nil,
            "SUPABASE_DB_URL": nil,
        ]) { app in
            try await app.testing().test(
                .GET,
                "/internal/custom-domain/verify-for-tls?domain=unknown.mcp.test",
                afterResponse: { res in
                    #expect(res.status == .unauthorized)
                }
            )

            try await app.testing().test(
                .GET,
                "/internal/custom-domain/verify-for-tls?domain=unknown.mcp.test",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-Internal-TLS-Ask-Secret", value: "tls-ask-secret")
                },
                afterResponse: { res in
                    #expect(res.status == .unprocessableEntity)
                }
            )

            let account = Account(githubId: 910_006, login: "tls-ask", email: "tls-ask@example.com")
            try await account.save(on: app.db)
            let project = Project(accountId: account.id!, name: "TLS Ask", slug: "tls-ask", subdomain: "known")
            try await project.save(on: app.db)

            try await app.testing().test(
                .GET,
                "/internal/custom-domain/verify-for-tls?domain=known.mcp.test",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-Internal-TLS-Ask-Secret", value: "tls-ask-secret")
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                }
            )

            project.suspendedAt = Date()
            try await project.save(on: app.db)
            try await app.testing().test(
                .GET,
                "/internal/custom-domain/verify-for-tls?domain=known.mcp.test",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-Internal-TLS-Ask-Secret", value: "tls-ask-secret")
                },
                afterResponse: { res in
                    #expect(res.status == .unprocessableEntity)
                }
            )
        }
    }

    @Test("GitHub webhook dispatch binds to hook id before signature verification")
    func githubWebhookDispatchBindsToHookIdBeforeSignatureVerification() async throws {
        try await withHardeningApp(appEnv: "prod", env: [
            "USE_SQLITE": "1",
            "USE_MEMORY_SESSIONS": "1",
            "SAAS_MCP_BASE_DOMAIN": "mcp.test",
            "DATABASE_URL": nil,
            "SUPABASE_DB_URL": nil,
        ]) { app in
            let account = Account(githubId: 910_007, login: "hook-bind", email: "hook-bind@example.com")
            try await account.save(on: app.db)
            let firstProject = Project(accountId: account.id!, name: "Hook First", slug: "hook-first", subdomain: "hookfirst")
            let secondProject = Project(accountId: account.id!, name: "Hook Second", slug: "hook-second", subdomain: "hooksecond")
            try await firstProject.save(on: app.db)
            try await secondProject.save(on: app.db)

            let first = RepoConnection(
                projectId: firstProject.id!,
                provider: "github",
                repoOwner: "Stygian-Tech",
                repoName: "shared-repo",
                defaultBranch: "main",
                webhookId: "hook-one",
                webhookSecret: "secret-one"
            )
            let second = RepoConnection(
                projectId: secondProject.id!,
                provider: "github",
                repoOwner: "Stygian-Tech",
                repoName: "shared-repo",
                defaultBranch: "main",
                webhookId: "hook-two",
                webhookSecret: "secret-two"
            )
            try await first.save(on: app.db)
            try await second.save(on: app.db)

            let payload = #"{"ref":"refs/heads/feature","repository":{"full_name":"Stygian-Tech/shared-repo","default_branch":"main"}}"#
            try await app.testing().test(
                .POST,
                "/webhooks/github",
                body: ByteBuffer(string: payload),
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-GitHub-Hook-ID", value: "hook-two")
                    req.headers.replaceOrAdd(name: "X-Hub-Signature-256", value: githubSignatureHeader(payload: payload, secret: "secret-two"))
                    req.headers.replaceOrAdd(name: .contentType, value: "application/json")
                },
                afterResponse: { res in
                    #expect(res.status == .ok, "github webhook status=\(res.status) body=\(res.body.string)")
                    #expect(res.body.string.contains(#""skipped":"not_default_branch""#))
                }
            )
        }
    }

    @Test("MCP resource subscriptions enforce per-subscriber caps")
    func mcpResourceSubscriptionsEnforcePerSubscriberCaps() {
        let subscriptions = McpResourceSubscriptions()
        let subscriber = UUID()
        for i in 0 ..< McpResourceSubscriptions.maxSubscriptionsPerSubscriber {
            #expect(subscriptions.subscribe(subscriberId: subscriber, uri: "resource://\(i)"))
        }
        #expect(subscriptions.subscribe(subscriberId: subscriber, uri: "resource://0"))
        #expect(!subscriptions.subscribe(subscriberId: subscriber, uri: "resource://overflow"))
        #expect(!subscriptions.subscribe(subscriberId: UUID(), uri: String(repeating: "a", count: McpResourceSubscriptions.maxUriLength + 1)))
    }

    @Test("RepoFetcher validates GitHub path segments")
    func repoFetcherValidatesGitHubPathSegments() {
        #expect(RepoFetcher.isValidGitHubOwnerOrRepo("Stygian-Tech"))
        #expect(RepoFetcher.isValidGitHubOwnerOrRepo("repo.name"))
        #expect(!RepoFetcher.isValidGitHubOwnerOrRepo("../owner"))
        #expect(!RepoFetcher.isValidGitHubOwnerOrRepo("owner/repo"))
        #expect(!RepoFetcher.isValidGitHubOwnerOrRepo(String(repeating: "a", count: 101)))

        #expect(RepoFetcher.isValidGitHubRef("feature/harden-oauth"))
        #expect(RepoFetcher.isValidGitHubRef("release-2026.06"))
        #expect(!RepoFetcher.isValidGitHubRef("../main"))
        #expect(!RepoFetcher.isValidGitHubRef("main?token=x"))
        #expect(!RepoFetcher.isValidGitHubRef(String(repeating: "a", count: 256)))
        #expect(RepoFetcher.pathSegmentEscape("feature/harden-oauth") == "feature%2Fharden-oauth")
    }

    @Test("RepoFetcher rejects archive symlink escapes and excessive entries")
    func repoFetcherRejectsArchiveAbuse() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("repo-archive-\(UUID().uuidString)")
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("repo-outside-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "secret".write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("escape"),
            withDestinationURL: outside
        )

        do {
            try RepoFetcher.validateExtractedArchive(root: root)
            Issue.record("Expected archive escape to be rejected")
        } catch RepoFetcherError.extractEscaped {
        } catch {
            Issue.record("Unexpected archive validation error: \(error)")
        }

        try FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let (apply, restore) = hardeningTemporaryEnv(["REPO_EXTRACT_MAX_ENTRIES": "1"])
        apply()
        defer { restore() }
        for i in 0 ... 100 {
            try "x".write(to: root.appendingPathComponent("file-\(i).txt"), atomically: true, encoding: .utf8)
        }
        do {
            try RepoFetcher.validateExtractedArchive(root: root)
            Issue.record("Expected excessive archive entries to be rejected")
        } catch RepoFetcherError.extractedArchiveTooManyEntries {
        } catch {
            Issue.record("Unexpected archive validation error: \(error)")
        }
    }

    @Test("OAuth handoff tokens are single use")
    func oauthHandoffTokensAreSingleUse() async throws {
        try await withHardeningApp(appEnv: "prod", env: [
            "USE_SQLITE": "1",
            "USE_MEMORY_SESSIONS": "1",
            "SAAS_MCP_BASE_DOMAIN": "mcp.test",
            "DATABASE_URL": nil,
            "SUPABASE_DB_URL": nil,
        ]) { app in
            let account = Account(githubId: 910_008, login: "handoff-single-use", email: "handoff-single-use@example.com")
            try await account.save(on: app.db)
            let token = try await OAuthHandoffService.issue(accountId: account.id!, on: app.db)

            let consumed = try await OAuthHandoffService.consume(token, on: app.db)
            #expect(consumed == account.id)

            let replay = try await OAuthHandoffService.consume(token, on: app.db)
            #expect(replay == nil)
        }
    }
}

private func withHardeningApp(
    appEnv: String,
    env: [String: String?],
    _ run: @Sendable @escaping (Application) async throws -> Void
) async throws {
    try await TestProcessEnvGate.run {
        let prevEnv = AppEnvironment._testOverrideAppEnv
        let (apply, restore) = hardeningTemporaryEnv(env)
        AppEnvironment._testOverrideAppEnv = appEnv
        apply()
        defer {
            restore()
            AppEnvironment._testOverrideAppEnv = prevEnv
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

private func postStripeWebhook(app: Application, payload: String, secret: String) async throws {
    let header = stripeSignatureHeader(payload: payload, secret: secret)
    try await app.testing().test(
        .POST,
        "/webhooks/stripe",
        body: ByteBuffer(string: payload),
        beforeRequest: { req in
            req.headers.replaceOrAdd(name: "Stripe-Signature", value: header)
            req.headers.replaceOrAdd(name: .contentType, value: "application/json")
        },
        afterResponse: { res in
            #expect(res.status == .ok, "stripe webhook status=\(res.status) body=\(res.body.string)")
        }
    )
}

private func stripeSubscriptionPayload(type: String, subscriptionId: String, customerId: String, status: String?) -> String {
    let statusField = status.map { #","status":"\#($0)""# } ?? ""
    return #"{"type":"\#(type)","data":{"object":{"id":"\#(subscriptionId)","customer":"\#(customerId)"\#(statusField)}}}"#
}

private func stripeSignatureHeader(payload: String, secret: String) -> String {
    let ts = String(Int(Date().timeIntervalSince1970))
    let signed = Data((ts + ".").utf8) + Data(payload.utf8)
    let key = StripeWebhookSignature.signingKey(from: secret)
    let mac = HMAC<SHA256>.authenticationCode(for: signed, using: SymmetricKey(data: key))
    let hex = mac.map { String(format: "%02x", $0) }.joined()
    return "t=\(ts),v1=\(hex)"
}

private func githubSignatureHeader(payload: String, secret: String) -> String {
    let key = SymmetricKey(data: Data(secret.utf8))
    let mac = HMAC<SHA256>.authenticationCode(for: Data(payload.utf8), using: key)
    let hex = mac.map { String(format: "%02x", $0) }.joined()
    return "sha256=\(hex)"
}

private func hardeningTemporaryEnv(_ overrides: [String: String?]) -> (() -> Void, () -> Void) {
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
