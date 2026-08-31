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

    @Test("Railway domain config validates scoped IDs, token, port, and HTTPS API URL")
    func railwayDomainConfigValidation() async throws {
        await TestProcessEnvGate.run {
            let (apply, restore) = hardeningTemporaryEnv([
                "RAILWAY_PROJECT_TOKEN": "railway_secret",
                "RAILWAY_PROJECT_ID": "3647f696-1766-459a-ac3f-0482e5a1f26c",
                "RAILWAY_ENVIRONMENT_ID": "9b29a079-8db3-47d5-81e5-6a20d747ad1f",
                "RAILWAY_SERVICE_ID": "5c1a6101-9c11-49fa-b384-7a71fee049c8",
                "RAILWAY_DOMAIN_API_URL": "https://backboard.railway.com/graphql/v2/",
                "RAILWAY_DOMAIN_TARGET_PORT": "8080",
            ])
            apply()
            defer { restore() }
            let config = RailwayDomainService.Config.fromEnvironment()
            #expect(config?.apiURL == "https://backboard.railway.com/graphql/v2")
            #expect(config?.targetPort == 8080)
            #expect(config?.authentication == .projectToken("railway_secret"))
        }

        await TestProcessEnvGate.run {
            let (apply, restore) = hardeningTemporaryEnv([
                "RAILWAY_PROJECT_TOKEN": "railway_secret",
                "RAILWAY_PROJECT_ID": "not-a-uuid",
                "RAILWAY_ENVIRONMENT_ID": "9b29a079-8db3-47d5-81e5-6a20d747ad1f",
                "RAILWAY_SERVICE_ID": "5c1a6101-9c11-49fa-b384-7a71fee049c8",
            ])
            apply()
            defer { restore() }
            #expect(RailwayDomainService.Config.fromEnvironment() == nil)
        }

        await TestProcessEnvGate.run {
            let (apply, restore) = hardeningTemporaryEnv([
                "RAILWAY_PROJECT_TOKEN": "railway_secret",
                "RAILWAY_PROJECT_ID": "3647f696-1766-459a-ac3f-0482e5a1f26c",
                "RAILWAY_ENVIRONMENT_ID": "9b29a079-8db3-47d5-81e5-6a20d747ad1f",
                "RAILWAY_SERVICE_ID": "5c1a6101-9c11-49fa-b384-7a71fee049c8",
                "RAILWAY_DOMAIN_API_URL": "http://backboard.railway.com/graphql/v2",
            ])
            apply()
            defer { restore() }
            #expect(RailwayDomainService.Config.fromEnvironment() == nil)
        }

        await TestProcessEnvGate.run {
            let (apply, restore) = hardeningTemporaryEnv([
                "RAILWAY_PROJECT_TOKEN": "railway_secret",
                "RAILWAY_PROJECT_ID": "3647f696-1766-459a-ac3f-0482e5a1f26c",
                "RAILWAY_ENVIRONMENT_ID": "9b29a079-8db3-47d5-81e5-6a20d747ad1f",
                "RAILWAY_SERVICE_ID": "5c1a6101-9c11-49fa-b384-7a71fee049c8",
                "RAILWAY_DOMAIN_TARGET_PORT": "70000",
            ])
            apply()
            defer { restore() }
            #expect(RailwayDomainService.Config.fromEnvironment() == nil)
        }
    }

    @Test("Railway domain HTTP errors redact response bodies")
    func railwayDomainHTTPErrorDescriptionRedactsBodies() {
        let error = RailwayDomainError.http(status: .badRequest, body: "secret-token-in-body")
        #expect(String(describing: error) == "HTTP 400")
        #expect(!String(describing: error).contains("secret-token-in-body"))
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
