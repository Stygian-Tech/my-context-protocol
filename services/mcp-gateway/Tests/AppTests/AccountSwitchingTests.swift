import Fluent
import FluentSQLiteDriver
import Foundation
import Testing
import Vapor
import VaporTesting
@testable import App

@Suite("Account switching", .serialized)
struct AccountSwitchingTests {
    @Test("A stale request cannot recreate a session deleted by logout")
    func revokedSessionCannotBeUpdated() async throws {
        let app = try await Application.make(.testing)
        do {
            app.databases.use(.sqlite(.memory), as: .sqlite)
            try await CreateAppSessions().prepare(on: app.db)
            let request = Request(application: app, on: app.eventLoopGroup.next())
            let driver = FluentSessionDriver()
            let staleData: SessionData = ["accountId": UUID().uuidString]
            let sessionID = try await driver.createSession(staleData, for: request).get()
            let updatedData: SessionData = ["accountId": UUID().uuidString]
            _ = try await driver.updateSession(sessionID, to: updatedData, for: request).get()
            #expect(try await driver.readSession(sessionID, for: request).get()?["accountId"] == updatedData["accountId"])
            try await driver.deleteSession(sessionID, for: request).get()
            do {
                _ = try await driver.updateSession(sessionID, to: staleData, for: request).get()
                Issue.record("A revoked session was restored")
            } catch let error as Abort {
                #expect(error.status == .unauthorized)
            }
            #expect(try await driver.readSession(sessionID, for: request).get() == nil)
            #expect(try await AppSessionRecord.query(on: app.db).count() == 0)
        } catch {
            try await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    @Test("GitHub account selection is explicit and unsupported prompts are rejected")
    func githubAccountPicker() async throws {
        try await TestProcessEnvGate.run {
            let overrides = [
                "GITHUB_CLIENT_ID": "account-switch-test",
                "GITHUB_OAUTH_REDIRECT_URI": "https://api.example.test/auth/github/callback",
                "FRONTEND_URL": "https://app.example.test",
                "ENCRYPTION_KEY": Data(repeating: 1, count: 32).base64EncodedString(),
            ]
            let original = Dictionary(uniqueKeysWithValues: overrides.keys.map {
                ($0, ProcessInfo.processInfo.environment[$0])
            })
            for (key, value) in overrides {
                setenv(key, value, 1)
            }
            defer {
                for key in overrides.keys {
                    if let value = original[key] ?? nil { setenv(key, value, 1) }
                    else { unsetenv(key) }
                }
            }
            let app = try await Application.make(.testing)
            app.get("auth", "github") { req async throws -> Response in
                try await AuthController.githubInitiate(req: req)
            }
            do {
                for suffix in ["", "?prompt=select_account"] {
                    try await app.testing().test(.GET, "/auth/github" + suffix, afterResponse: { response in
                        #expect(response.status == .seeOther)
                        let location = try #require(response.headers.first(name: .location))
                        let components = try #require(URLComponents(string: location))
                        #expect(components.host == "github.com")
                        let items = components.queryItems ?? []
                        #expect(items.first(where: { $0.name == "prompt" })?.value == (suffix.isEmpty ? nil : "select_account"))
                        let state = try #require(items.first(where: { $0.name == "state" })?.value)
                        #expect(try SignedOAuthState.verifyGitHubOAuth(state: state) == "https://app.example.test/")
                    })
                }
                try await app.testing().test(.GET, "/auth/github?prompt=consent", afterResponse: { response in
                    #expect(response.status == .badRequest)
                })
            } catch {
                try await app.asyncShutdown()
                throw error
            }
            try await app.asyncShutdown()
        }
    }
}
