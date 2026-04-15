import Crypto
import Fluent
import Foundation
import NIOCore
import Testing
import Vapor
import VaporTesting
@testable import App

@Suite("API key revocation", .serialized)
struct ApiKeyRevocationTests {
    @Test("List excludes revoked keys by default; include_revoked returns all")
    func listFiltering() async throws {
        try await withApiKeyRevocationApp { app in
            let account = Account(githubId: 910_001, login: "key-revoke-1", email: "k1@example.com")
            try await account.save(on: app.db)
            let project = Project(
                accountId: account.id!,
                name: "Key Revoke Proj",
                slug: "key-revoke-proj",
                subdomain: "krsub"
            )
            try await project.save(on: app.db)

            let active = Self.apiKeyRow(projectId: project.id!, prefix: "mcp_active111", status: "active")
            let revoked = Self.apiKeyRow(projectId: project.id!, prefix: "mcp_revoked11", status: "revoked")
            try await active.save(on: app.db)
            try await revoked.save(on: app.db)

            let pid = project.id!.uuidString
            let req = Self.authedRequest(
                app: app,
                method: .GET,
                path: "/projects/\(pid)/api-keys",
                account: account
            )
            Self.applyParams(req, ("id", pid))
            let defaultList = try await ProjectController.listApiKeys(req: req)
            #expect(defaultList.count == 1)
            #expect(defaultList[0].status == "active")

            let reqAll = Self.authedRequest(
                app: app,
                method: .GET,
                path: "/projects/\(pid)/api-keys",
                query: "include_revoked=true",
                account: account
            )
            Self.applyParams(reqAll, ("id", pid))
            let all = try await ProjectController.listApiKeys(req: reqAll)
            #expect(all.count == 2)
            let statuses = Set(all.map(\.status))
            #expect(statuses == ["active", "revoked"])
        }
    }

    @Test("Revoke sets status; MCP rejects revoked key; PATCH rename on revoked conflicts")
    func revokeAndAuth() async throws {
        try await withApiKeyRevocationApp { app in
            let account = Account(githubId: 910_002, login: "key-revoke-2", email: "k2@example.com")
            try await account.save(on: app.db)
            let project = Project(
                accountId: account.id!,
                name: "Key Revoke Proj 2",
                slug: "key-revoke-proj-2",
                subdomain: "krsub2"
            )
            try await project.save(on: app.db)

            let rawKey = "mcp_testrevokekey000000000000000"
            let hashString = Self.sha256Hex(rawKey)
            let prefix = String(rawKey.prefix(12))
            let keyRow = ApiKey(
                projectId: project.id!,
                name: "integration",
                keyPrefix: prefix,
                keyHash: hashString,
                status: "active"
            )
            try await keyRow.save(on: app.db)
            let kid = keyRow.id!.uuidString
            let pid = project.id!.uuidString

            let initBody =
                #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{}}}"#

            try await app.testing().test(
                .POST,
                "/mcp",
                body: ByteBuffer(string: initBody),
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-API-Key", value: rawKey)
                    req.headers.replaceOrAdd(name: .contentType, value: "application/json")
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                }
            )

            let del = Self.authedRequest(
                app: app,
                method: .DELETE,
                path: "/projects/\(pid)/api-keys/\(kid)",
                account: account
            )
            Self.applyParams(del, ("id", pid), ("keyId", kid))
            let delRes = try await ProjectController.revokeApiKey(req: del)
            #expect(delRes.status == .noContent)

            let del2 = Self.authedRequest(
                app: app,
                method: .DELETE,
                path: "/projects/\(pid)/api-keys/\(kid)",
                account: account
            )
            Self.applyParams(del2, ("id", pid), ("keyId", kid))
            let delRes2 = try await ProjectController.revokeApiKey(req: del2)
            #expect(delRes2.status == .noContent)

            try await app.testing().test(
                .POST,
                "/mcp",
                body: ByteBuffer(string: initBody),
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-API-Key", value: rawKey)
                    req.headers.replaceOrAdd(name: .contentType, value: "application/json")
                },
                afterResponse: { res in
                    #expect(res.status == .unauthorized)
                }
            )

            let patch = Self.authedRequest(
                app: app,
                method: .PATCH,
                path: "/projects/\(pid)/api-keys/\(kid)",
                account: account,
                jsonBody: #"{"name":"nope"}"#
            )
            patch.parameters.set("id", to: pid)
            patch.parameters.set("keyId", to: kid)
            await #expect(throws: Abort.self) {
                _ = try await ProjectController.updateApiKey(req: patch)
            }
        }
    }

    private static func sha256Hex(_ raw: String) -> String {
        let hash = SHA256.hash(data: Data(raw.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private static func apiKeyRow(projectId: UUID, prefix: String, status: String) -> ApiKey {
        let fakeRaw = prefix + String(repeating: "0", count: max(0, 32 - prefix.count))
        let hash = Self.sha256Hex(fakeRaw)
        return ApiKey(
            projectId: projectId,
            name: nil,
            keyPrefix: prefix,
            keyHash: hash,
            status: status
        )
    }

    private static func applyParams(_ req: Request, _ pairs: (String, String)...) {
        var p = req.parameters
        for (k, v) in pairs {
            p.set(k, to: v)
        }
        req.parameters = p
    }

    private static func authedRequest(
        app: Application,
        method: HTTPMethod,
        path: String,
        query: String? = nil,
        account: Account,
        jsonBody: String? = nil
    ) -> Request {
        let pathAndQuery: String =
            if let query {
                "\(path)?\(query)"
            } else {
                path
            }
        let url = URI(string: "http://localhost\(pathAndQuery)")
        var headers = HTTPHeaders()
        if jsonBody != nil {
            headers.replaceOrAdd(name: .contentType, value: "application/json")
        }
        let req = Request(
            application: app,
            method: method,
            url: url,
            headers: headers,
            collectedBody: jsonBody.map { ByteBuffer(string: $0) },
            logger: app.logger,
            on: app.eventLoopGroup.next()
        )
        req.storage[AccountKey.self] = account
        return req
    }
}

private func withApiKeyRevocationApp(
    _ run: @Sendable @escaping (Application) async throws -> Void
) async throws {
    try await TestProcessEnvGate.shared.run {
        let prev = AppEnvironment._testOverrideAppEnv
        AppEnvironment._testOverrideAppEnv = "local"
        let (apply, restore) = apiKeyRevocationTemporaryEnv([
            "USE_SQLITE": "1",
            "USE_MEMORY_SESSIONS": "1",
            "MCP_OAUTH_ENABLED": "0",
            "FRONTEND_URL": "http://localhost:3000",
            "DATABASE_URL": nil,
            "SUPABASE_DB_URL": nil,
        ])
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

private func apiKeyRevocationTemporaryEnv(_ overrides: [String: String?]) -> (() -> Void, () -> Void) {
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
