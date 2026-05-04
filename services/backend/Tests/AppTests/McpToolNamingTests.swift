import Crypto
import Fluent
import Foundation
import NIOCore
import Testing
import Vapor
import VaporTesting
@testable import App

@Suite("MCP tool naming (colon-free wire names)", .serialized)
struct McpToolNamingTests {
    @Test("tools/list uses mycontext_catalog and bare slugs; legacy colon names rejected on tools/call")
    func toolsListAndCallWireNames() async throws {
        try await withMcpToolNamingApp { app in
            let account = Account(githubId: 920_001, login: "mcp-name-1", email: "m1@example.com")
            try await account.save(on: app.db)
            let project = Project(
                accountId: account.id!,
                name: "MCP Name Proj",
                slug: "mcp-name-proj",
                subdomain: "mcpnsub"
            )
            try await project.save(on: app.db)

            let rawKey = "mcp_testnamingkey000000000000000"
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

            let release = Release(projectId: project.id!, commitSha: "abc", status: "ready")
            try await release.save(on: app.db)

            let pkg = SkillPackage(
                releaseId: release.id!,
                path: "skills/foo/SKILL.md",
                name: "demo-skill",
                validationStatus: "valid"
            )
            try await pkg.save(on: app.db)

            let compiled = CompiledSkill(
                releaseId: release.id!,
                skillPackageId: pkg.id!,
                path: pkg.path,
                name: pkg.name,
                summary: "Demo summary",
                skillBody: "# Demo",
                exposureType: "tool",
                riskLevel: "low",
                repoSpecific: false,
                status: "ready"
            )
            try await compiled.save(on: app.db)

            let schemaJson = CapabilitySchemaBuilder.toolInputSchemaJson(
                description: "d",
                summary: "s"
            )
            let cap = CapabilityDef(
                compiledSkillId: compiled.id!,
                capabilityName: "demo-skill",
                type: "tool",
                schemaJson: schemaJson,
                sideEffectLevel: "read"
            )
            try await cap.save(on: app.db)

            project.activeReleaseId = release.id
            try await project.save(on: app.db)

            let listBody = #"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#

            try await app.testing().test(
                .POST,
                "/mcp",
                body: ByteBuffer(string: listBody),
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-API-Key", value: rawKey)
                    req.headers.replaceOrAdd(name: .contentType, value: "application/json")
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let text = res.body.string
                    #expect(text.contains("\"name\":\"mycontext_catalog\""))
                    #expect(text.contains("\"name\":\"demo-skill\""))
                    #expect(!text.contains("mycontext:catalog"))
                    #expect(!text.contains("skill:demo-skill"))
                }
            )

            func postToolsCall(name: String) async throws -> HTTPStatus {
                let escaped = name.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                let body =
                    #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"\#(escaped)","arguments":{}}}"#
                var status: HTTPStatus = .badRequest
                try await app.testing().test(
                    .POST,
                    "/mcp",
                    body: ByteBuffer(string: body),
                    beforeRequest: { req in
                        req.headers.replaceOrAdd(name: "X-API-Key", value: rawKey)
                        req.headers.replaceOrAdd(name: .contentType, value: "application/json")
                    },
                    afterResponse: { res in
                        status = res.status
                    }
                )
                return status
            }

            #expect(try await postToolsCall(name: "mycontext_catalog") == .ok)
            #expect(try await postToolsCall(name: "demo-skill") == .ok)
            #expect(try await postToolsCall(name: "mycontext:catalog") == .notFound)
            #expect(try await postToolsCall(name: "skill:demo-skill") == .notFound)
        }
    }

    @Test("prompts/list and prompts/get use bare slug; legacy skill: prefix rejected")
    func promptsWireNames() async throws {
        try await withMcpToolNamingApp { app in
            let account = Account(githubId: 920_002, login: "mcp-name-2", email: "m2@example.com")
            try await account.save(on: app.db)
            let project = Project(
                accountId: account.id!,
                name: "MCP Name Proj 2",
                slug: "mcp-name-proj-2",
                subdomain: "mcpnsub2"
            )
            try await project.save(on: app.db)

            let rawKey = "mcp_testnamingkey200000000000000"
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

            let release = Release(projectId: project.id!, commitSha: "def", status: "ready")
            try await release.save(on: app.db)

            let pkg = SkillPackage(
                releaseId: release.id!,
                path: "skills/bar/SKILL.md",
                name: "guidance-skill",
                validationStatus: "valid"
            )
            try await pkg.save(on: app.db)

            let compiled = CompiledSkill(
                releaseId: release.id!,
                skillPackageId: pkg.id!,
                path: pkg.path,
                name: pkg.name,
                summary: "Guidance summary",
                skillBody: "Body",
                exposureType: "guidance",
                riskLevel: "low",
                repoSpecific: false,
                status: "ready"
            )
            try await compiled.save(on: app.db)

            let schemaJson = CapabilitySchemaBuilder.promptMetaJson()
            let cap = CapabilityDef(
                compiledSkillId: compiled.id!,
                capabilityName: "guidance-skill",
                type: "prompt",
                schemaJson: schemaJson,
                sideEffectLevel: "read"
            )
            try await cap.save(on: app.db)

            project.activeReleaseId = release.id
            try await project.save(on: app.db)

            let listBody = #"{"jsonrpc":"2.0","id":4,"method":"prompts/list","params":{}}"#

            try await app.testing().test(
                .POST,
                "/mcp",
                body: ByteBuffer(string: listBody),
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-API-Key", value: rawKey)
                    req.headers.replaceOrAdd(name: .contentType, value: "application/json")
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let text = res.body.string
                    #expect(text.contains("\"name\":\"guidance-skill\""))
                    #expect(!text.contains("skill:guidance-skill"))
                }
            )

            let getBody =
                #"{"jsonrpc":"2.0","id":5,"method":"prompts/get","params":{"name":"guidance-skill","arguments":{}}}"#

            try await app.testing().test(
                .POST,
                "/mcp",
                body: ByteBuffer(string: getBody),
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-API-Key", value: rawKey)
                    req.headers.replaceOrAdd(name: .contentType, value: "application/json")
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                }
            )

            let getLegacy =
                #"{"jsonrpc":"2.0","id":6,"method":"prompts/get","params":{"name":"skill:guidance-skill","arguments":{}}}"#

            try await app.testing().test(
                .POST,
                "/mcp",
                body: ByteBuffer(string: getLegacy),
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-API-Key", value: rawKey)
                    req.headers.replaceOrAdd(name: .contentType, value: "application/json")
                },
                afterResponse: { res in
                    #expect(res.status == .badRequest)
                }
            )
        }
    }

    private static func sha256Hex(_ raw: String) -> String {
        let hash = SHA256.hash(data: Data(raw.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

private func withMcpToolNamingApp(
    _ run: @Sendable @escaping (Application) async throws -> Void
) async throws {
    try await TestProcessEnvGate.run {
        let prev = AppEnvironment._testOverrideAppEnv
        AppEnvironment._testOverrideAppEnv = "local"
        let (apply, restore) = mcpToolNamingTemporaryEnv([
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

private func mcpToolNamingTemporaryEnv(_ overrides: [String: String?]) -> (() -> Void, () -> Void) {
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
