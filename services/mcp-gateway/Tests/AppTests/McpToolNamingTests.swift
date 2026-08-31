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
    @Test("Streamable HTTP headers validate versions, accepts, and origins")
    func streamableHTTPHeaders() async throws {
        try await withMcpToolNamingApp { app in
            let account = Account(githubId: 920_000, login: "mcp-headers", email: "headers@example.com")
            try await account.save(on: app.db)
            let project = Project(accountId: account.id!, name: "MCP Headers", slug: "mcp-headers", subdomain: "mcpheaders")
            try await project.save(on: app.db)
            let rawKey = "mcp_headerkey0000000000000000000"
            let keyRow = ApiKey(
                projectId: project.id!, name: "headers", keyPrefix: String(rawKey.prefix(12)),
                keyHash: Self.sha256Hex(rawKey), status: "active"
            )
            try await keyRow.save(on: app.db)
            let listBody = #"{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}"#

            func request(
                body: String = #"{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}"#,
                version: String? = nil,
                accept: String? = nil,
                origin: String? = nil
            ) async throws -> (HTTPStatus, String) {
                var status = HTTPStatus.internalServerError
                var responseBody = ""
                try await app.testing().test(.POST, "/mcp", body: ByteBuffer(string: body), beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-API-Key", value: rawKey)
                    req.headers.replaceOrAdd(name: .contentType, value: "application/json")
                    if let version { req.headers.replaceOrAdd(name: "MCP-Protocol-Version", value: version) }
                    if let accept { req.headers.replaceOrAdd(name: .accept, value: accept) }
                    if let origin { req.headers.replaceOrAdd(name: .origin, value: origin) }
                }, afterResponse: {
                    status = $0.status
                    responseBody = $0.body.string
                })
                return (status, responseBody)
            }

            let headerless = try await request(body: listBody)
            #expect(headerless.0 == .ok)
            #expect(!headerless.1.contains("\"outputSchema\""))
            #expect(!headerless.1.contains("\"annotations\""))
            let latest = try await request(
                body: listBody,
                version: "2025-11-25",
                accept: "application/json, text/event-stream"
            )
            #expect(latest.0 == .ok)
            #expect(latest.1.contains("\"outputSchema\""))
            let legacyCall = try await request(
                body: #"{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"resolve_context","arguments":{"request":"inspect legacy response"}}}"#,
                version: "2025-03-26"
            )
            #expect(legacyCall.0 == .ok)
            #expect(!legacyCall.1.contains("\"structuredContent\""))
            #expect(!legacyCall.1.contains("resource_link"))
            #expect(legacyCall.1.contains("\"type\":\"text\""))
            #expect((try await request(version: "2099-01-01")).0 == .badRequest)
            #expect((try await request(version: " ")).0 == .badRequest)
            #expect((try await request(accept: "application/json")).0 == .badRequest)
            #expect((try await request(origin: "https://attacker.example")).0 == .forbidden)
            #expect((try await request(origin: "http://localhost:3000")).0 == .ok)

            let wrongJSONRPC = try await request(
                body: #"{"jsonrpc":"1.0","id":2,"method":"tools/list","params":{}}"#
            )
            #expect(wrongJSONRPC.0 == .badRequest)
            #expect(wrongJSONRPC.1.contains("\"code\":-32600"))
            let missingId = try await request(body: #"{"jsonrpc":"2.0","method":"tools/list","params":{}}"#)
            #expect(missingId.0 == .badRequest)
            #expect(missingId.1.contains("non-null id"))
            let nullId = try await request(body: #"{"jsonrpc":"2.0","id":null,"method":"tools/list","params":{}}"#)
            #expect(nullId.0 == .badRequest)
            let notification = try await request(body: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
            #expect(notification.0 == .accepted)
            #expect(notification.1.isEmpty)
            let notificationWithId = try await request(
                body: #"{"jsonrpc":"2.0","id":3,"method":"notifications/initialized"}"#
            )
            #expect(notificationWithId.0 == .badRequest)
            #expect(notificationWithId.1.contains("notifications must not include an id"))

            func getStream(version: String? = nil, accept: String? = nil) async throws -> HTTPStatus {
                var status = HTTPStatus.internalServerError
                try await app.testing().test(.GET, "/mcp", beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-API-Key", value: rawKey)
                    if let version { req.headers.replaceOrAdd(name: "MCP-Protocol-Version", value: version) }
                    if let accept { req.headers.replaceOrAdd(name: .accept, value: accept) }
                }, afterResponse: { status = $0.status })
                return status
            }
            #expect(try await getStream(version: "2099-01-01", accept: "text/event-stream") == .badRequest)
            #expect(try await getStream(version: "2025-11-25", accept: "application/json") == .badRequest)

            let unknownTool = try await request(
                body: #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"missing-tool","arguments":{}}}"#,
                version: "2025-11-25"
            )
            #expect(unknownTool.0 == .badRequest)
            #expect(unknownTool.1.contains("\"code\":-32602"))
        }
    }

    @Test("tools/list defaults to three canonical tools; aliases stay hidden and legacy compiled tools require opt-in")
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
            let collidingCap = CapabilityDef(
                compiledSkillId: compiled.id!,
                capabilityName: MCPConstants.resolveContextToolName,
                type: "tool",
                schemaJson: schemaJson,
                sideEffectLevel: "read"
            )
            try await collidingCap.save(on: app.db)

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
                    req.headers.replaceOrAdd(name: "MCP-Protocol-Version", value: "2025-11-25")
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let text = res.body.string
                    let object = try! JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
                    let result = object["result"] as! [String: Any]
                    let tools = result["tools"] as! [[String: Any]]
                    let names = tools.compactMap { $0["name"] as? String }
                    #expect(names.filter { $0 == "resolve_context" }.count == 1)
                    #expect(names.filter { $0 == "get_skill" }.count == 1)
                    #expect(names.filter { $0 == "report_skill_feedback" }.count == 1)
                    #expect(Set(names) == Set(MCPConstants.runtimeToolNames))
                    #expect(!names.contains("demo-skill"))
                    #expect(!names.contains("mycontext_catalog"))
                    #expect(!names.contains("discover_skills"))
                    #expect(!names.contains("list_capabilities"))
                    #expect(!text.contains("mycontext:catalog"))
                    #expect(!text.contains("skill:demo-skill"))
                    #expect(text.contains("\"outputSchema\""))
                    #expect(text.contains("\"annotations\""))
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
                        req.headers.replaceOrAdd(name: "MCP-Protocol-Version", value: "2025-11-25")
                    },
                    afterResponse: { res in
                        status = res.status
                    }
                )
                return status
            }

            #expect(try await postToolsCall(name: "mycontext_catalog") == .ok)
            #expect(try await postToolsCall(name: "discover_skills") == .ok)
            #expect(try await postToolsCall(name: "list_capabilities") == .ok)
            #expect(try await postToolsCall(name: "demo-skill") == .badRequest)
            #expect(try await postToolsCall(name: "mycontext:catalog") == .badRequest)
            #expect(try await postToolsCall(name: "skill:demo-skill") == .badRequest)

            let settings = ProjectRuntimeSettings()
            settings.$project.id = project.id!
            settings.telemetryEnabled = true
            settings.telemetryRetentionDays = 30
            settings.semanticEnabled = false
            settings.feedbackIssueCreationEnabled = false
            settings.providerPreferencesJson = #"{"legacy_compiled_tools_enabled":true}"#
            try await settings.save(on: app.db)

            try await app.testing().test(
                .POST,
                "/mcp",
                body: ByteBuffer(string: listBody),
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-API-Key", value: rawKey)
                    req.headers.replaceOrAdd(name: .contentType, value: "application/json")
                    req.headers.replaceOrAdd(name: "MCP-Protocol-Version", value: "2025-11-25")
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    let object = try! JSONSerialization.jsonObject(with: Data(res.body.string.utf8)) as! [String: Any]
                    let result = object["result"] as! [String: Any]
                    let tools = result["tools"] as! [[String: Any]]
                    let names = tools.compactMap { $0["name"] as? String }
                    #expect(names.contains("demo-skill"))
                    #expect(names.filter { $0 == "resolve_context" }.count == 1)
                }
            )
            #expect(try await postToolsCall(name: "demo-skill") == .ok)
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

    @Test("mycontext_catalog delegates to canonical resolution while preserving legacy request wrappers")
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
            #expect(overview.contains("Resolved by `resolve_context`"))
            #expect(overview.contains("structuredContent"))

            let route = try await Self.postCatalogCall(
                argumentsJson: #"{"mode":"route","task":"I need to plan backend architecture changes","limit":"3"}"#,
                rawKey: rawKey,
                app: app
            )
            #expect(route.contains("# MCP catalog route"))
            #expect(route.contains("Resolved by `resolve_context`"))
            #expect(route.contains("resolutionTrace"))

            let resourceSkill = try await Self.postCatalogCall(
                argumentsJson: #"{"mode":"skill","skill":"ctx://skill/architecture-context"}"#,
                rawKey: rawKey,
                app: app
            )
            #expect(resourceSkill.contains("\"isError\":true"))
            #expect(resourceSkill.contains("not active in this project"))

            let promptSkill = try await Self.postCatalogCall(
                argumentsJson: #"{"mode":"skill","skill":"review-guidance"}"#,
                rawKey: rawKey,
                app: app
            )
            #expect(promptSkill.contains("\"isError\":true"))
            #expect(promptSkill.contains("not active in this project"))

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
            let packageFile = SkillPackageFile()
            packageFile.$skillPackage.id = pkg.id!
            packageFile.path = "references/guide.md"
            packageFile.content = Data("Reference package guidance".utf8)
            packageFile.contentType = "text/markdown"
            packageFile.byteCount = packageFile.content.count
            packageFile.checksum = Self.sha256Hex("Reference package guidance")
            try await packageFile.save(on: app.db)
            project.activeReleaseId = release.id; try await project.save(on: app.db)

            let inventory = #"[{"server":"linear","name":"create_issue","description":"Create issue","provider":"linear"}]"#
            let resolved = try await Self.postRuntimeCall(
                name: "resolve_context",
                argumentsJson: #"{"request":"preserve follow-up issue","event":"non_blocking_issue_discovered","context":{"workspace":"runtime"},"available_tools":\#(inventory)}"#,
                rawKey: rawKey,
                app: app
            )
            #expect(resolved.contains("incidental-issues"))
            #expect(resolved.contains("create_issue"))
            #expect(resolved.contains("capabilityBindings"))
            #expect(resolved.contains("\"structuredContent\""))
            #expect(resolved.contains("\"isError\":false"))
            let resolvedEnvelope = try #require(JSONSerialization.jsonObject(with: Data(resolved.utf8)) as? [String: Any])
            let resolvedResult = try #require(resolvedEnvelope["result"] as? [String: Any])
            let resolvedStructured = try #require(resolvedResult["structuredContent"] as? [String: Any])
            let resolvedContent = try #require(resolvedResult["content"] as? [[String: Any]])
            let fallbackText = try #require(resolvedContent.first?["text"] as? String)
            let fallbackObject = try #require(JSONSerialization.jsonObject(with: Data(fallbackText.utf8)) as? [String: Any])
            #expect(resolvedStructured["traceId"] as? String == fallbackObject["traceId"] as? String)
            #expect(resolvedStructured["schemaVersion"] as? Int == fallbackObject["schemaVersion"] as? Int)

            let invalid = try await Self.postRuntimeCall(
                name: "resolve_context",
                argumentsJson: "{}",
                rawKey: rawKey,
                app: app,
                expectedStatus: .badRequest
            )
            #expect(invalid.contains("\"code\":-32602"))
            #expect(invalid.contains("request is required"))

            let discovered = try await Self.postRuntimeCall(name: "discover_skills", arguments: ["query": "found unrelated bug", "event": "non_blocking_issue_discovered"], rawKey: rawKey, app: app)
            #expect(discovered.contains("eventCanonical"))
            #expect(discovered.contains("incidental-issues"))
            let fetched = try await Self.postRuntimeCall(name: "get_skill", arguments: ["skill_id": "incidental-issues", "version": "1.0.0"], rawKey: rawKey, app: app)
            #expect(fetched.contains("# Preserve issues"))
            #expect(fetched.contains("resource_link"))
            #expect(fetched.replacingOccurrences(of: "\\/", with: "/").contains("ctx://skill/incidental-issues/file/references/guide.md?version=1.0.0"))
            let fetchedFile = try await Self.postRuntimeCall(
                name: "get_skill",
                arguments: ["skill_id": "incidental-issues", "version": "1.0.0", "path": "references/guide.md"],
                rawKey: rawKey,
                app: app
            )
            #expect(fetchedFile.contains("Reference package guidance"))
            #expect(fetchedFile.contains("\"encoding\":\"utf-8\""))

            let resourceBody = #"{"jsonrpc":"2.0","id":11,"method":"resources/read","params":{"uri":"ctx://skill/incidental-issues/file/references/guide.md?version=1.0.0"}}"#
            try await app.testing().test(.POST, "/mcp", body: ByteBuffer(string: resourceBody), beforeRequest: { request in
                request.headers.replaceOrAdd(name: "X-API-Key", value: rawKey)
                request.headers.replaceOrAdd(name: .contentType, value: "application/json")
                request.headers.replaceOrAdd(name: "MCP-Protocol-Version", value: "2025-11-25")
            }, afterResponse: { response in
                #expect(response.status == .ok)
                #expect(response.body.string.contains("Reference package guidance"))
            })
            let capabilities = try await Self.postRuntimeCall(name: "list_capabilities", arguments: ["skill_id": "incidental-issues", "available_tools": inventory], rawKey: rawKey, app: app)
            #expect(capabilities.contains("issue.create"))
            let staleFeedback = try await Self.postRuntimeCall(
                name: "report_skill_feedback",
                argumentsJson: #"{"skill_id":"incidental-issues","version":"0.9.0","category":"missing_guidance","summary":"Stale observation","evidence":"Observed against an inactive version."}"#,
                rawKey: rawKey,
                app: app
            )
            #expect(staleFeedback.contains("\"isError\":true"))
            #expect(try await SkillFeedbackRecord.query(on: app.db).count() == 0)
            let missingEvidence = try await Self.postRuntimeCall(
                name: "report_skill_feedback",
                argumentsJson: #"{"skill_id":"incidental-issues","version":"1.0.0","category":"missing_guidance","summary":"Missing evidence"}"#,
                rawKey: rawKey,
                app: app,
                expectedStatus: .badRequest
            )
            #expect(missingEvidence.contains("\"code\":-32602"))
            #expect(try await SkillFeedbackRecord.query(on: app.db).count() == 0)
            let feedback = try await Self.postRuntimeCall(
                name: "report_skill_feedback",
                argumentsJson: #"{"skill_id":"incidental-issues","version":"1.0.0","category":"missing_guidance","summary":"Explain duplicate search","evidence":"The resolver omitted the duplicate-search step in trace example 42.","create_issue":false}"#,
                rawKey: rawKey,
                app: app
            )
            #expect(feedback.contains("effectStatus"))
            #expect(feedback.contains("draft"))
            #expect(feedback.contains("\"structuredContent\""))
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
        return try await postRuntimeCall(name: name, argumentsJson: argumentsJson, rawKey: rawKey, app: app)
    }

    private static func postRuntimeCall(
        name: String,
        argumentsJson: String,
        rawKey: String,
        app: Application,
        expectedStatus: HTTPStatus = .ok
    ) async throws -> String {
        let body = #"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"\#(name)","arguments":\#(argumentsJson)}}"#
        var result = ""
        try await app.testing().test(.POST, "/mcp", body: ByteBuffer(string: body), beforeRequest: { req in
            req.headers.replaceOrAdd(name: "X-API-Key", value: rawKey)
            req.headers.replaceOrAdd(name: .contentType, value: "application/json")
            req.headers.replaceOrAdd(name: "MCP-Protocol-Version", value: "2025-11-25")
        }, afterResponse: { response in
            #expect(response.status == expectedStatus)
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
                req.headers.replaceOrAdd(name: "MCP-Protocol-Version", value: "2025-11-25")
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
