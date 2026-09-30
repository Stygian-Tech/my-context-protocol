import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting
@testable import App

@Suite("GitHub App installation entry point", .serialized)
struct GitHubAppInstallRouteTests {
    @Test("Installation requires a session and an owned project before a repository is selected")
    func projectScopedInstallation() async throws {
        try await withGitHubAppInstallRouteApp { app in
            let suffix = UUID().uuidString.lowercased()
            let owner = Account(githubId: Int64.random(in: 100_000_000...900_000_000), login: "install-owner-" + suffix)
            let stranger = Account(githubId: Int64.random(in: 100_000_000...900_000_000), login: "install-stranger-" + suffix)
            try await owner.save(on: app.db)
            try await stranger.save(on: app.db)
            let project = Project(accountId: owner.id!, name: "Empty repository picker", slug: suffix, subdomain: suffix)
            try await project.save(on: app.db)
            let path = "/auth/github/app/install?project_id=\(project.id!)"

            func cookie(for account: Account) async throws -> String {
                let request = Request(application: app, method: .GET, url: URI(string: path),
                    version: .http1_1, headers: [:], remoteAddress: nil, logger: app.logger,
                    on: app.eventLoopGroup.next())
                let sessionId = try await app.sessions.driver.createSession(["accountId": account.id!.uuidString], for: request).get()
                return "\(app.sessions.configuration.cookieName)=\(sessionId.string)"
            }
            let ownerCookie = try await cookie(for: owner)
            let strangerCookie = try await cookie(for: stranger)
            try await app.testing().test(.GET, path, afterResponse: { response in
                #expect(response.status == .unauthorized)
            })
            try await app.testing().test(.GET, path, beforeRequest: { request in
                request.headers.replaceOrAdd(name: .cookie, value: strangerCookie)
            }, afterResponse: { response in
                #expect(response.status == .notFound)
            })
            #expect(try await GitHubAppInstallIntent.query(on: app.db).count() == 0)

            try await app.testing().test(.GET, path, beforeRequest: { request in
                request.headers.replaceOrAdd(name: .cookie, value: ownerCookie)
            }, afterResponse: { response in
                #expect(response.status == .seeOther)
                let location = try #require(response.headers.first(name: .location))
                let components = try #require(URLComponents(string: location))
                #expect(components.scheme == "https")
                #expect(components.host == "github.com")
                #expect(components.path == "/apps/mcp-route-test/installations/new")
                let state = try #require(components.queryItems?.first(where: { $0.name == "state" })?.value)
                let intentId = try #require(UUID(uuidString: state))
                let intent = try #require(try await GitHubAppInstallIntent.find(intentId, on: app.db))
                #expect(intent.$project.id == project.id!)
                #expect(intent.$account.id == owner.id!)
                #expect(intent.owner == nil)
                #expect(intent.repo == nil)
                #expect(intent.expiresAt > Date())
            })
            #expect(try await GitHubAppInstallIntent.query(on: app.db).count() == 1)
        }
    }
}

private func withGitHubAppInstallRouteApp(_ run: @Sendable @escaping (Application) async throws -> Void) async throws {
    try await TestProcessEnvGate.run {
        let keys = ["USE_MEMORY_SESSIONS", "DISABLE_SKILL_USAGE_RETENTION_SCHEDULER", "GITHUB_APP_SLUG"]
        let saved = Dictionary(uniqueKeysWithValues: keys.map { ($0, ProcessInfo.processInfo.environment[$0]) })
        setenv("USE_MEMORY_SESSIONS", "1", 1)
        setenv("DISABLE_SKILL_USAGE_RETENTION_SCHEDULER", "1", 1)
        setenv("GITHUB_APP_SLUG", "mcp-route-test", 1)
        defer {
            for key in keys {
                if let value = saved[key] ?? nil { setenv(key, value, 1) }
                else { unsetenv(key) }
            }
        }
        let app = try await Application.make(.testing)
        app.logger.logLevel = .warning
        do { try await configure(app); try await run(app) }
        catch { try await app.asyncShutdown(); throw error }
        try await app.asyncShutdown()
    }
}
