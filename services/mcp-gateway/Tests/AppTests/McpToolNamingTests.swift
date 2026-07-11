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

    @Test("mycontext_catalog routes across tools resources and prompts and can load full skill bodies")
    func catalogRouteAndSkillModes() async throws {
        try await withMcpToolNamingApp { app in
            let account = Account(githubId: 920_003, login: "mcp-name-3", email: "m3@example.com")
            try await account.save(on: app.db)
            let project = Project(
                accountId: account.id!,
                name: "MCP Catalog Proj",
                slug: "mcp-catalog-proj",
                subdomain: "mcpcatsub"
            )
            try await project.save(on: app.db)

            let rawKey = "mcp_testcatalogkey00000000000000"
            let hashString = Self.sha256Hex(rawKey)
            let keyRow = ApiKey(
                projectId: project.id!,
                name: "integration",
                keyPrefix: String(rawKey.prefix(12)),
                keyHash: hashString,
                status: "active"
            )
            try await keyRow.save(on: app.db)

            let release = Release(projectId: project.id!, commitSha: "catalog", status: "ready")
            try await release.save(on: app.db)

            try await Self.insertCatalogSkill(
                release: release,
                name: "frontend-debugging",
                type: "tool",
                summary: "Debug rendered frontend behavior",
                body: "# Frontend Debugging\nUse browser screenshots and DOM inspection.",
                useWhen: ["debugging frontend rendering problems"],
                on: app.db
            )
            try await Self.insertCatalogSkill(
                release: release,
                name: "architecture-context",
                type: "resource",
                summary: "Architecture context for backend planning",
                body: "# Architecture Context\nBackend architecture details live here.",
                useWhen: ["planning backend architecture changes"],
                on: app.db
            )
            try await Self.insertCatalogSkill(
                release: release,
                name: "review-guidance",
                type: "prompt",
                summary: "Review guidance for code changes",
                body: "# Review Guidance\nPrioritize bugs and regressions.",
                useWhen: ["reviewing code changes"],
                on: app.db
            )

            project.activeReleaseId = release.id
            try await project.save(on: app.db)

            let overview = try await Self.postCatalogCall(argumentsJson: "{}", rawKey: rawKey, app: app)
            #expect(overview.contains("# MCP catalog"))
            #expect(overview.contains("frontend-debugging"))
            #expect(overview.contains("architecture-context"))
            #expect(overview.contains("review-guidance"))

            let route = try await Self.postCatalogCall(
                argumentsJson: #"{"mode":"route","task":"I need to plan backend architecture changes","limit":"3"}"#,
                rawKey: rawKey,
                app: app
            )
            #expect(route.contains("# MCP catalog route"))
            #expect(route.contains("Architecture context"))
            #expect(route.contains("resources/read ctx://skill/architecture-context"))
            #expect(route.contains("tools/call mycontext_catalog"))
            #expect(route.contains("prompts/get review-guidance"))
            #expect(route.contains("tools/call frontend-debugging"))

            let resourceSkill = try await Self.postCatalogCall(
                argumentsJson: #"{"mode":"skill","skill":"ctx://skill/architecture-context"}"#,
                rawKey: rawKey,
                app: app
            )
            #expect(resourceSkill.contains("# Architecture Context"))
            #expect(resourceSkill.contains("Exposure: resource"))
            #expect(resourceSkill.contains("Backend architecture details live here."))

            let promptSkill = try await Self.postCatalogCall(
                argumentsJson: #"{"mode":"skill","skill":"review-guidance"}"#,
                rawKey: rawKey,
                app: app
            )
            #expect(promptSkill.contains("# Review Guidance"))
            #expect(promptSkill.contains("Exposure: prompt"))
            #expect(promptSkill.contains("Prioritize bugs and regressions."))

            let catalogCalls = try await RequestLog.query(on: app.db)
                .filter(\.$project.$id == project.id!)
                .filter(\.$mcpCapabilityKind == "tool")
                .filter(\.$mcpCapabilityKey == MCPConstants.catalogToolName)
                .count()
            #expect(catalogCalls >= 4)
        }
    }

    @Test("portable runtime tools resolve, retrieve, bind capabilities, discover events, and draft feedback")
    func portableRuntimeTools() async throws {
        try await withMcpToolNamingApp { app in
            let account = Account(githubId: 920_004, login: "runtime", email: "runtime@example.com")
            try await account.save(on: app.db)
            let project = Project(accountId: account.id!, name: "Runtime", slug: "runtime", subdomain: "runtime")
            try await project.save(on: app.db)
            let rawKey = "mcp_testruntimekey000000000000000"
            let key = ApiKey(projectId: project.id!, name: "runtime", keyPrefix: String(rawKey.prefix(12)), keyHash: Self.sha256Hex(rawKey), status: "active")
            try await key.save(on: app.db)
            let release = Release(projectId: project.id!, commitSha: "runtime-sha", status: "ready")
            try await release.save(on: app.db)
            let pkg = SkillPackage(releaseId: release.id!, path: "incidental/SKILL.md", name: "incidental-issues", validationStatus: "valid")
            try await pkg.save(on: app.db)
            let compiled = CompiledSkill(releaseId: release.id!, skillPackageId: pkg.id!, path: pkg.path, name: pkg.name,
                summary: "Preserve follow-up issues", skillBody: "# Preserve issues", exposureType: "resource", riskLevel: "low", repoSpecific: false, status: "ready")
            let document = CompiledSkillDocument(
                schemaVersion: 1, id: pkg.name, name: pkg.name, description: "Preserve follow-up issues", kind: .operating,
                scope: .workspace, activation: .init(mode: .event, intents: ["follow-up issue"], events: ["non_blocking_issue_discovered"], tags: [], examples: []),
                enforcement: .required, priority: 80,
                requires: [.init(capability: "issue.create", required: true, onMissing: .returnDraft)], conflictsWith: [],
                instructions: "# Preserve issues", source: .init(repository: "stygian/skills", path: pkg.path, revision: "runtime-sha", checksum: "abc"),
                version: "1.0.0", lifecycle: nil, validation: .init(clarificationRequired: false, missingFields: [], warnings: [])
            )
            compiled.skillId = document.id; compiled.kind = document.kind.rawValue; compiled.scope = document.scope.rawValue
            compiled.activationMode = document.activation.mode.rawValue; compiled.enforcement = document.enforcement.rawValue
            compiled.priority = document.priority; compiled.version = document.version; compiled.sourceChecksum = document.source.checksum
            compiled.canonicalJson = SkillRuntimeJSON.encode(document); compiled.clarificationJson = "[]"; compiled.clarificationRequired = false
            try await compiled.save(on: app.db)
            project.activeReleaseId = release.id; try await project.save(on: app.db)

            let inventory = #"[{"server":"linear","name":"create_issue","description":"Create issue","provider":"linear"}]"#
            let resolved = try await Self.postRuntimeCall(name: "resolve_context", arguments: ["request": "preserve follow-up issue", "available_tools": inventory], rawKey: rawKey, app: app)
            #expect(resolved.contains("incidental-issues"))
            #expect(resolved.contains("create_issue"))
            #expect(resolved.contains("capabilityBindings"))
            let discovered = try await Self.postRuntimeCall(name: "discover_skills", arguments: ["query": "found unrelated bug", "event": "non_blocking_issue_discovered"], rawKey: rawKey, app: app)
            #expect(discovered.contains("eventCanonical"))
            #expect(discovered.contains("incidental-issues"))
            let fetched = try await Self.postRuntimeCall(name: "get_skill", arguments: ["skill_id": "incidental-issues", "version": "1.0.0"], rawKey: rawKey, app: app)
            #expect(fetched.contains("# Preserve issues"))
            let capabilities = try await Self.postRuntimeCall(name: "list_capabilities", arguments: ["skill_id": "incidental-issues", "available_tools": inventory], rawKey: rawKey, app: app)
            #expect(capabilities.contains("issue.create"))
            let feedback = try await Self.postRuntimeCall(name: "report_skill_feedback", arguments: ["skill_id": "incidental-issues", "version": "1.0.0", "category": "missing_guidance", "summary": "Explain duplicate search"], rawKey: rawKey, app: app)
            #expect(feedback.contains("effectStatus"))
            #expect(feedback.contains("draft"))
            #expect(try await SkillFeedbackRecord.query(on: app.db).count() == 1)
        }
    }

    private static func sha256Hex(_ raw: String) -> String {
        let hash = SHA256.hash(data: Data(raw.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private static func postRuntimeCall(name: String, arguments: [String: String], rawKey: String, app: Application) async throws -> String {
        let argumentsData = try JSONEncoder().encode(arguments)
        let argumentsJson = String(data: argumentsData, encoding: .utf8)!
        let body = #"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"\#(name)","arguments":\#(argumentsJson)}}"#
        var result = ""
        try await app.testing().test(.POST, "/mcp", body: ByteBuffer(string: body), beforeRequest: { req in
            req.headers.replaceOrAdd(name: "X-API-Key", value: rawKey)
            req.headers.replaceOrAdd(name: .contentType, value: "application/json")
        }, afterResponse: { response in
            #expect(response.status == .ok)
            result = response.body.string
        })
        return result
    }

    private static func insertCatalogSkill(
        release: Release,
        name: String,
        type: String,
        summary: String,
        body: String,
        useWhen: [String],
        on db: Database
    ) async throws {
        let pkg = SkillPackage(
            releaseId: release.id!,
            path: "skills/\(name)/SKILL.md",
            name: name,
            validationStatus: "valid"
        )
        try await pkg.save(on: db)
        let compiled = CompiledSkill(
            releaseId: release.id!,
            skillPackageId: pkg.id!,
            path: pkg.path,
            name: name,
            summary: summary,
            skillBody: body,
            exposureType: type,
            riskLevel: "low",
            repoSpecific: false,
            status: "ready"
        )
        try await compiled.save(on: db)
        let rule = RoutingRule(
            compiledSkillId: compiled.id!,
            useWhenJson: String(data: try JSONEncoder().encode(useWhen), encoding: .utf8),
            avoidWhenJson: nil,
            failureModesJson: nil,
            invokeFirst: type == "resource"
        )
        try await rule.save(on: db)
        let schemaJson: String
        switch type {
        case "resource":
            schemaJson = CapabilitySchemaBuilder.resourceMetaJson(
                skillName: name,
                useWhen: useWhen,
                avoidWhen: nil,
                failureModes: nil,
                invokeFirst: type == "resource"
            )
        case "prompt":
            schemaJson = CapabilitySchemaBuilder.promptMetaJson()
        default:
            schemaJson = CapabilitySchemaBuilder.toolInputSchemaJson(description: summary, summary: summary)
        }
        let cap = CapabilityDef(
            compiledSkillId: compiled.id!,
            capabilityName: name,
            type: type,
            schemaJson: schemaJson,
            sideEffectLevel: "read"
        )
        try await cap.save(on: db)
    }

    private static func postCatalogCall(
        argumentsJson: String,
        rawKey: String,
        app: Application
    ) async throws -> String {
        let body =
            #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"mycontext_catalog","arguments":\#(argumentsJson)}}"#
        var text = ""
        try await app.testing().test(
            .POST,
            "/mcp",
            body: ByteBuffer(string: body),
            beforeRequest: { req in
                req.headers.replaceOrAdd(name: "X-API-Key", value: rawKey)
                req.headers.replaceOrAdd(name: .contentType, value: "application/json")
            },
            afterResponse: { res in
                #expect(res.status == .ok)
                text = res.body.string
            }
        )
        return text.replacingOccurrences(of: "\\/", with: "/")
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
