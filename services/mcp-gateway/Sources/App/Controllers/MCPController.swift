import Fluent
import MCPServerKit
import Vapor

private struct MCPDispatchOutput {
    let response: Response
    let httpStatus: Int
    let jsonRpcErrorCode: Int?
    let jsonRpcErrorMessage: String?
}

struct MCPController {
    static func handle(req: Request) async throws -> Response {
        let start = Date()
        guard let project = req.storage[ProjectKey.self] else {
            return Response(status: .unauthorized, body: .init(string: "No project"))
        }
        guard let projectId = project.id else {
            return Response(status: .internalServerError, body: .init(string: "Invalid project"))
        }
        if let transportError = validateTransportHeaders(req: req) {
            return transportError
        }
        let requestProtocolVersion = effectiveProtocolVersion(req: req)

        let clientName: String? = mcpClientLabel(req: req)

        let body: JSONRPCRequest
        do {
            body = try req.content.decode(JSONRPCRequest.self)
            req.logger.devTrace("mcp_rpc decoded method=\(body.method.rawValue) projectId=\(projectId.uuidString)")
        } catch {
            req.logger.mcpTrace("mcp_rpc decode_failed projectId=\(projectId.uuidString)")
            let res = try await jsonRPCError(id: nil, code: -32700, message: "Parse error").encodeResponse(
                status: .badRequest,
                for: req
            )
            req.attachMcpCatalogRevisionHeader(to: res)
            let latencyMs = Int(Date().timeIntervalSince(start) * 1000)
            try? await RequestLog(
                projectId: projectId,
                releaseId: project.activeReleaseId,
                clientId: clientName,
                method: "parse_error",
                latencyMs: latencyMs,
                status: String(res.status.code),
                errorCode: "-32700",
                errorMessage: "JSON-RPC body could not be decoded",
                mcpCapabilityKind: nil,
                mcpCapabilityKey: nil
            ).save(on: req.db)
            return res
        }

        if let envelopeError = validateJSONRPCEnvelope(body) {
            let out = try await serveRpcError(
                id: body.id == .null ? nil : body.id,
                code: -32600,
                message: envelopeError,
                req: req
            )
            req.attachMcpCatalogRevisionHeader(to: out.response)
            return out.response
        }

        let out: MCPDispatchOutput
        switch body.method {
        case "initialize":
            req.logger.mcpTrace("mcp dispatch handler=initialize projectId=\(projectId.uuidString)")
            out = try await handleInitialize(req: req, project: project, params: body.params, id: body.id)
        case "tools/list":
            req.logger.mcpTrace("mcp dispatch handler=tools/list projectId=\(projectId.uuidString)")
            out = try await handleToolsList(
                req: req,
                project: project,
                params: body.params,
                id: body.id,
                protocolVersion: requestProtocolVersion
            )
        case "tools/call":
            req.logger.mcpTrace("mcp dispatch handler=tools/call projectId=\(projectId.uuidString)")
            out = try await handleToolsCall(
                req: req,
                projectId: projectId,
                params: body.params,
                id: body.id,
                protocolVersion: requestProtocolVersion
            )
        case "resources/list":
            req.logger.mcpTrace("mcp dispatch handler=resources/list projectId=\(projectId.uuidString)")
            out = try await handleResourcesList(req: req, project: project, params: body.params, id: body.id)
        case "resources/read":
            req.logger.mcpTrace("mcp dispatch handler=resources/read projectId=\(projectId.uuidString)")
            out = try await handleResourcesRead(req: req, project: project, params: body.params, id: body.id)
        case "resources/subscribe":
            req.logger.mcpTrace("mcp dispatch handler=resources/subscribe projectId=\(projectId.uuidString)")
            out = try await handleResourcesSubscribe(req: req, params: body.params, id: body.id)
        case "resources/unsubscribe":
            req.logger.mcpTrace("mcp dispatch handler=resources/unsubscribe projectId=\(projectId.uuidString)")
            out = try await handleResourcesUnsubscribe(req: req, params: body.params, id: body.id)
        case "prompts/list":
            req.logger.mcpTrace("mcp dispatch handler=prompts/list projectId=\(projectId.uuidString)")
            out = try await handlePromptsList(req: req, project: project, params: body.params, id: body.id)
        case "prompts/get":
            req.logger.mcpTrace("mcp dispatch handler=prompts/get projectId=\(projectId.uuidString)")
            out = try await handlePromptsGet(req: req, project: project, params: body.params, id: body.id)
        case "notifications/initialized", "notifications/cancelled":
            // Lifecycle / cancellation JSON-RPC notifications: no `id`, no result body (MCP over HTTP).
            req.logger.mcpTrace("mcp dispatch handler=\(body.method.rawValue) projectId=\(projectId.uuidString)")
            out = serveNotificationAck()
        default:
            req.logger.mcpTrace(
                "mcp dispatch handler=method_not_found projectId=\(projectId.uuidString) requestedMethod=\(body.method.rawValue)"
            )
            out = try await serveRpcError(id: body.id, code: -32601, message: "Method not found", req: req)
        }

        let latencyMs = Int(Date().timeIntervalSince(start) * 1000)
        let errCodeStr = out.jsonRpcErrorCode.map { String($0) } ?? "-"
        req.logger.mcpTrace(
            "mcp_rpc done projectId=\(projectId.uuidString) method=\(body.method.rawValue) httpStatus=\(out.httpStatus) jsonRpcError=\(errCodeStr) latencyMs=\(latencyMs)"
        )
        let releaseId = project.activeReleaseId
        let capTag = Self.mcpCapabilityInvocationTag(method: body.method.rawValue, params: body.params)
        try? await RequestLog(
            projectId: projectId,
            releaseId: releaseId,
            clientId: clientName,
            method: body.method.rawValue,
            latencyMs: latencyMs,
            status: String(out.httpStatus),
            errorCode: out.jsonRpcErrorCode.map { String($0) },
            errorMessage: out.jsonRpcErrorMessage,
            mcpCapabilityKind: capTag?.kind,
            mcpCapabilityKey: capTag?.key
        ).save(on: req.db)

        req.attachMcpCatalogRevisionHeader(to: out.response)
        return out.response
    }

    static func validateTransportHeaders(req: Request) -> Response? {
        if let rawVersion = req.headers.first(name: "MCP-Protocol-Version") {
            let version = rawVersion.trimmingCharacters(in: .whitespacesAndNewlines)
            guard MCPServerKit.MCPProtocolVersion(rawValue: version) != nil else {
                return Response(status: .badRequest, body: .init(string: "Unsupported MCP-Protocol-Version"))
            }
        }
        if let accept = req.headers.first(name: .accept), accept != "*/*" {
            let normalized = accept.lowercased()
            let valid = req.method == .GET
                ? normalized.contains("text/event-stream")
                : normalized.contains("application/json") && normalized.contains("text/event-stream")
            guard valid else {
                let expected = req.method == .GET ? "text/event-stream" : "application/json and text/event-stream"
                return Response(status: .badRequest, body: .init(string: "Accept must include \(expected)"))
            }
        }
        if let rawOrigin = req.headers.first(name: .origin) {
            let origin = rawOrigin.trimmingCharacters(in: .whitespacesAndNewlines)
            let configured = (Environment.get("MCP_ALLOWED_ORIGINS") ?? "")
                .split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let allowed = Set(AppFrontendURL.allowedOriginBases() + configured)
            guard allowed.contains(where: { $0.caseInsensitiveCompare(origin) == .orderedSame }) else {
                return Response(status: .forbidden, body: .init(string: "Invalid origin"))
            }
        }
        return nil
    }

    static func effectiveProtocolVersion(req: Request) -> MCPServerKit.MCPProtocolVersion {
        guard let raw = req.headers.first(name: "MCP-Protocol-Version")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              let version = MCPServerKit.MCPProtocolVersion(rawValue: raw) else {
            return .missingHTTPHeaderFallback
        }
        return version
    }

    private static func supportsRichToolResults(_ version: MCPServerKit.MCPProtocolVersion) -> Bool {
        switch version {
        case .v2025_06_18, .v2025_11_25: return true
        case .v2024_11_05, .v2025_03_26: return false
        }
    }

    private static func validateJSONRPCEnvelope(_ body: JSONRPCRequest) -> String? {
        guard body.jsonrpc == "2.0" else { return "Invalid Request: jsonrpc must be 2.0" }
        let isNotification = body.method == .notificationsInitialized || body.method == .notificationsCancelled
        if isNotification {
            guard body.id == nil else { return "Invalid Request: notifications must not include an id" }
        } else {
            guard let id = body.id, id != .null else {
                return "Invalid Request: requests must include a non-null id"
            }
        }
        return nil
    }

    private static func serveSuccess(_ content: some Content, req: Request) async throws -> MCPDispatchOutput {
        let response = try await content.encodeResponse(for: req)
        return MCPDispatchOutput(
            response: response,
            httpStatus: Int(response.status.code),
            jsonRpcErrorCode: nil,
            jsonRpcErrorMessage: nil
        )
    }

    private static func serveNotificationAck() -> MCPDispatchOutput {
        let response = Response(status: .accepted)
        return MCPDispatchOutput(
            response: response,
            httpStatus: Int(response.status.code),
            jsonRpcErrorCode: nil,
            jsonRpcErrorMessage: nil
        )
    }

    /// HTTP status for JSON-RPC error payloads so proxies and logs reflect failure (not only `error` in the body).
    private static func httpStatusForJsonRpcError(code: Int) -> HTTPStatus {
        switch code {
        case -32700, -32600: return .badRequest
        case -32601: return .notFound
        case -32602: return .badRequest
        case -32603: return .internalServerError
        default: return .badRequest
        }
    }

    private static func serveRpcError(
        id: JSONRPCId?,
        code: Int,
        message: String,
        req: Request,
        httpStatus: HTTPStatus? = nil
    ) async throws -> MCPDispatchOutput {
        req.logger.mcpTrace("mcp rpc_error jsonRpcCode=\(code) message=\(message)")
        let status = httpStatus ?? httpStatusForJsonRpcError(code: code)
        let response = try await jsonRPCError(id: id, code: code, message: message).encodeResponse(status: status, for: req)
        return MCPDispatchOutput(
            response: response,
            httpStatus: Int(response.status.code),
            jsonRpcErrorCode: code,
            jsonRpcErrorMessage: message
        )
    }

    private static func jsonRPCError(id: JSONRPCId?, code: Int, message: String) -> some Content {
        struct ErrorPayload: Content {
            let jsonrpc: String
            let id: JSONRPCId?
            let error: JSONRPCError
        }
        return ErrorPayload(jsonrpc: "2.0", id: id, error: JSONRPCError(code: code, message: message))
    }

    private static func handleInitialize(
        req: Request,
        project: Project,
        params: JSONRPCParams?,
        id: JSONRPCId?
    ) async throws -> MCPDispatchOutput {
        struct InitPayload: Content {
            let jsonrpc: String
            let id: JSONRPCId?
            let result: InitializeResult
        }
        guard let projectId = project.id else {
            return try await serveRpcError(id: id, code: -32603, message: "Invalid project", req: req)
        }
        let negotiated = MCPServerKit.MCPProtocolVersion.negotiated(requested: params?.protocolVersion)
        let dash = projectDashboardURL(projectId: projectId)
        let instructions = MCPAgentCopy.initializeInstructions(projectName: project.name, projectDashboardURL: dash)
        let result = InitializeResult(
            protocolVersion: negotiated,
            capabilities: ServerCapabilities(
                tools: ToolsCapability(listChanged: true),
                resources: ResourcesCapability(subscribe: true, listChanged: true),
                prompts: PromptsCapability(listChanged: true)
            ),
            serverInfo: ServerInfo(
                name: "MyContextProtocol",
                version: MCPConstants.serverVersion,
                title: "MyContextProtocol — \(project.name)",
                description: MCPAgentCopy.serverDescription(projectName: project.name),
                websiteUrl: dash
            ),
            instructions: instructions
        )
        return try await serveSuccess(InitPayload(jsonrpc: "2.0", id: id, result: result), req: req)
    }

    private static func projectDashboardURL(projectId: UUID) -> String? {
        guard let base = AppFrontendURL.normalizedBase() else { return nil }
        return "\(base)/projects/\(projectId.uuidString)"
    }

    private static func runtimeTools(protocolVersion: MCPServerKit.MCPProtocolVersion) -> [MCPTool] {
        let descriptions = [
            "resolve_context": "Task bootstrap: returns ordered active and suggested skills, conflicts, provenance, capability bindings, and a resolution trace.",
            "get_skill": "Returns the complete versioned compiled skill document, including original Markdown and provenance.",
            "report_skill_feedback": "Stores version-specific skill feedback and returns an issue draft; never implies an external side effect occurred."
        ]
        let titles = [
            "resolve_context": "Resolve project context",
            "get_skill": "Get complete skill",
            "report_skill_feedback": "Report skill feedback",
        ]
        return MCPConstants.runtimeToolNames.map { name in
            let isReadOnly = name != MCPConstants.reportSkillFeedbackToolName
            if supportsRichToolResults(protocolVersion) {
                return MCPTool(
                    name: name,
                    description: descriptions[name],
                    inputSchema: CapabilitySchemaBuilder.runtimeToolInputSchema(name: name),
                    title: titles[name],
                    outputSchema: CapabilitySchemaBuilder.runtimeToolOutputSchema(name: name),
                    annotations: MCPToolAnnotations(
                        title: titles[name],
                        readOnlyHint: isReadOnly,
                        destructiveHint: false,
                        idempotentHint: isReadOnly,
                        openWorldHint: false
                    )
                )
            }
            return MCPTool(
                name: name,
                description: descriptions[name],
                inputSchema: CapabilitySchemaBuilder.runtimeToolInputSchema(name: name)
            )
        }
    }

    private static func handleToolsList(
        req: Request,
        project: Project,
        params: JSONRPCParams?,
        id: JSONRPCId?,
        protocolVersion: MCPServerKit.MCPProtocolVersion
    ) async throws -> MCPDispatchOutput {
        struct ToolsListPayload: Content {
            let jsonrpc: String
            let id: JSONRPCId?
            let result: ToolsListResult
        }

        var tools = runtimeTools(protocolVersion: protocolVersion)
        let legacyEnabled = try await ToolHandlers.legacyCompiledToolsEnabled(db: req.db, projectId: project.id!)
        if legacyEnabled, let releaseId = project.activeReleaseId {
            let compiledSkillIds = try await MCPCatalogService.readyCompiledSkillIds(releaseId: releaseId, db: req.db)
            let capabilityDefs = try await MCPCatalogService.capabilityDefs(
                compiledSkillIds: compiledSkillIds,
                types: ["tool"],
                db: req.db
            )
            let legacyTools = capabilityDefs.compactMap { cap -> MCPTool? in
                guard !MCPConstants.isReservedRuntimeToolName(cap.capabilityName) else {
                    req.logger.warning("mcp tools/list suppressed compiled capability with reserved runtime name=\(cap.capabilityName)")
                    return nil
                }
                let compiled = cap.compiledSkill
                let hints = McpCatalogMarkdown.routingHints(for: compiled)
                return MCPTool(
                    name: cap.capabilityName,
                    description: MCPAgentCopy.toolDescription(baseSummary: compiled.summary, hints: hints),
                    inputSchema: InputSchema.fromCapabilitySchemaJson(cap.schemaJson)
                )
            }.sorted { $0.name < $1.name }
            tools.append(contentsOf: legacyTools)
        }
        let scope = "tools:\(project.id!.uuidString):\(project.activeReleaseId?.uuidString ?? "none"):\(legacyEnabled)"
        let page: MCPPaginationPage<MCPTool>
        do { page = try MCPPaginator.page(tools, cursor: params?.cursor, scope: scope) }
        catch { return try await serveRpcError(id: id, code: -32602, message: "Invalid pagination cursor", req: req) }
        req.logger.mcpTrace("mcp tools/list count=\(page.items.count) legacyCompiledTools=\(legacyEnabled)")
        let listResult = ToolsListResult(tools: page.items, nextCursor: page.nextCursor)
        return try await serveSuccess(ToolsListPayload(jsonrpc: "2.0", id: id, result: listResult), req: req)
    }

    private static func handleToolsCall(
        req: Request,
        projectId: UUID,
        params: JSONRPCParams?,
        id: JSONRPCId?,
        protocolVersion: MCPServerKit.MCPProtocolVersion
    ) async throws -> MCPDispatchOutput {
        struct ToolCallPayload: Content {
            let jsonrpc: String
            let id: JSONRPCId?
            let result: ToolCallResult
        }

        guard let name = params?.name else {
            return try await serveRpcError(id: id, code: -32602, message: "Invalid params: missing name", req: req)
        }
        let arguments = params?.arguments ?? [:]
        let argKeys = arguments.keys.sorted().joined(separator: ",")
        req.logger.mcpTrace("mcp tools/call tool=\(name) argKeys=[\(argKeys)]")

        do {
            let output = try await ToolHandlers.handle(
                name: name,
                arguments: arguments,
                db: req.db,
                projectId: projectId
            )
            let richResults = supportsRichToolResults(protocolVersion)
            let content = richResults ? output.content : output.content.filter {
                if case .text = $0 { return true }
                return false
            }
            let toolResult = ToolCallResult(
                content: content,
                structuredContent: richResults ? output.structuredContent : nil,
                isError: false
            )
            return try await serveSuccess(ToolCallPayload(jsonrpc: "2.0", id: id, result: toolResult), req: req)
        } catch let ToolHandlerError.unknownTool(name: unknown) {
            return try await serveRpcError(id: id, code: -32602, message: "Unknown tool: \(unknown)", req: req)
        } catch let abort as Abort {
            if abort.status == .badRequest {
                return try await serveRpcError(id: id, code: -32602, message: abort.reason, req: req)
            }
            let error = JSONValue.object([
                "error": .object([
                    "code": .string("tool_failure"),
                    "message": .string(abort.reason),
                ]),
            ])
            let richResults = supportsRichToolResults(protocolVersion)
            let toolResult = ToolCallResult(
                text: SkillRuntimeJSON.encode(error),
                structuredContent: richResults ? error : nil,
                isError: true
            )
            return try await serveSuccess(ToolCallPayload(jsonrpc: "2.0", id: id, result: toolResult), req: req)
        } catch {
            let message: String
            if AppEnvironment.deployKind() == .prod {
                message = "Internal error"
                req.logger.error("MCP tools/call failed: \(String(reflecting: error))")
            } else {
                message = error.localizedDescription
            }
            let failure = JSONValue.object([
                "error": .object([
                    "code": .string("tool_failure"),
                    "message": .string(message),
                ]),
            ])
            let richResults = supportsRichToolResults(protocolVersion)
            let toolResult = ToolCallResult(
                text: SkillRuntimeJSON.encode(failure),
                structuredContent: richResults ? failure : nil,
                isError: true
            )
            return try await serveSuccess(ToolCallPayload(jsonrpc: "2.0", id: id, result: toolResult), req: req)
        }
    }

    private static func handleResourcesList(req: Request, project: Project, params: JSONRPCParams?, id: JSONRPCId?) async throws -> MCPDispatchOutput {
        struct Payload: Content {
            let jsonrpc: String
            let id: JSONRPCId?
            let result: ResourcesListResult
        }
        guard let releaseId = project.activeReleaseId else {
            if params?.cursor != nil {
                return try await serveRpcError(id: id, code: -32602, message: "Invalid pagination cursor", req: req)
            }
            return try await serveSuccess(
                Payload(jsonrpc: "2.0", id: id, result: ResourcesListResult(resources: [], nextCursor: nil)),
                req: req
            )
        }
        let compiledSkillIds = try await MCPCatalogService.readyCompiledSkillIds(releaseId: releaseId, db: req.db)
        let caps = try await MCPCatalogService.capabilityDefs(
            compiledSkillIds: compiledSkillIds,
            types: ["resource"],
            db: req.db
        )
        let resources: [MCPResource] = caps.compactMap { cap in
            guard let meta = CapabilitySchemaBuilder.parseResourceMeta(cap.schemaJson) else { return nil }
            let compiled = cap.compiledSkill
            return MCPResource(
                uri: meta.uri,
                name: compiled.name,
                description: compiled.summary,
                mimeType: meta.mimeType,
                useWhen: meta.useWhen,
                avoidWhen: meta.avoidWhen,
                failureModes: meta.failureModes,
                invokeFirst: meta.invokeFirst
            )
        }.sorted { $0.uri < $1.uri }
        let page: MCPPaginationPage<MCPResource>
        do {
            page = try MCPPaginator.page(
                resources,
                cursor: params?.cursor,
                scope: "resources:\(project.id!.uuidString):\(releaseId.uuidString)"
            )
        } catch {
            return try await serveRpcError(id: id, code: -32602, message: "Invalid pagination cursor", req: req)
        }
        req.logger.mcpTrace("mcp resources/list count=\(page.items.count)")
        return try await serveSuccess(
            Payload(jsonrpc: "2.0", id: id, result: ResourcesListResult(resources: page.items, nextCursor: page.nextCursor)),
            req: req
        )
    }

    private static func handleResourcesRead(req: Request, project: Project, params: JSONRPCParams?, id: JSONRPCId?) async throws -> MCPDispatchOutput {
        struct Payload: Content {
            let jsonrpc: String
            let id: JSONRPCId?
            let result: ResourceReadResult
        }
        guard let uri = params?.uri?.trimmingCharacters(in: .whitespacesAndNewlines), !uri.isEmpty else {
            return try await serveRpcError(id: id, code: -32602, message: "Invalid params: missing uri", req: req)
        }
        let uriLog = uri.count > 120 ? String(uri.prefix(120)) + "…" : uri
        req.logger.mcpTrace("mcp resources/read uri=\(uriLog)")
        do {
            if let reference = try SkillPackageResourceService.parse(uri: uri) {
                let (compiled, document) = try await SkillPackageResourceService.activeCompiledSkill(
                    projectId: project.id!,
                    skillId: reference.skillId,
                    version: reference.version,
                    db: req.db
                )
                if let path = reference.path {
                    let file = try await SkillPackageResourceService.file(compiled: compiled, path: path, db: req.db)
                    let mimeType = file.contentType ?? "application/octet-stream"
                    let contents = if let text = String(data: file.content, encoding: .utf8) {
                        ResourceContents(uri: uri, mimeType: mimeType, text: text)
                    } else {
                        ResourceContents(uri: uri, mimeType: mimeType, blob: file.content.base64EncodedString())
                    }
                    return try await serveSuccess(Payload(jsonrpc: "2.0", id: id, result: .init(contents: [contents])), req: req)
                }
                let contents = ResourceContents(uri: uri, mimeType: "text/markdown", text: document.instructions)
                return try await serveSuccess(Payload(jsonrpc: "2.0", id: id, result: .init(contents: [contents])), req: req)
            }
        } catch let abort as Abort {
            return try await serveRpcError(id: id, code: -32602, message: abort.reason, req: req)
        }
        guard let releaseId = project.activeReleaseId else {
            return try await serveRpcError(id: id, code: -32602, message: "No active release", req: req)
        }
        let compiledSkillIds = try await MCPCatalogService.readyCompiledSkillIds(releaseId: releaseId, db: req.db)
        let caps = try await MCPCatalogService.capabilityDefs(
            compiledSkillIds: compiledSkillIds,
            types: ["resource"],
            db: req.db
        )
        for cap in caps {
            if let meta = CapabilitySchemaBuilder.parseResourceMeta(cap.schemaJson), meta.uri == uri {
                let compiled = cap.compiledSkill
                var body = compiled.skillBody ?? compiled.summary ?? ""
                if let preamble = CapabilitySchemaBuilder.resourceReadPreamble(
                    meta: meta,
                    skillSummary: compiled.summary
                ) {
                    body = preamble + body
                }
                let read = ResourceReadResult(contents: [
                    ResourceContents(uri: uri, mimeType: meta.mimeType, text: body)
                ])
                return try await serveSuccess(Payload(jsonrpc: "2.0", id: id, result: read), req: req)
            }
        }
        return try await serveRpcError(id: id, code: -32602, message: "Resource not found", req: req)
    }

    private struct MCPJsonEmpty: Content {}

    private struct JsonRpcDataResult<D: Content>: Content {
        let jsonrpc: String
        let id: JSONRPCId?
        let result: D
    }

    private static func handleResourcesSubscribe(req: Request, params: JSONRPCParams?, id: JSONRPCId?) async throws -> MCPDispatchOutput {
        guard let uri = params?.uri?.trimmingCharacters(in: .whitespacesAndNewlines), !uri.isEmpty else {
            return try await serveRpcError(id: id, code: -32602, message: "Invalid params: missing uri", req: req)
        }
        guard let sid = mcpResourceSubscriberId(req: req) else {
            return try await serveRpcError(id: id, code: -32603, message: "Missing subscriber context", req: req)
        }
        guard req.application.mcpResourceSubscriptions.subscribe(subscriberId: sid, uri: uri) else {
            return try await serveRpcError(id: id, code: -32000, message: "Resource subscription limit exceeded", req: req)
        }
        let uriLog = uri.count > 80 ? String(uri.prefix(80)) + "…" : uri
        req.logger.mcpTrace("mcp resources/subscribe uri=\(uriLog)")
        return try await serveSuccess(
            JsonRpcDataResult(jsonrpc: "2.0", id: id, result: MCPJsonEmpty()),
            req: req
        )
    }

    private static func handleResourcesUnsubscribe(req: Request, params: JSONRPCParams?, id: JSONRPCId?) async throws -> MCPDispatchOutput {
        guard let uri = params?.uri?.trimmingCharacters(in: .whitespacesAndNewlines), !uri.isEmpty else {
            return try await serveRpcError(id: id, code: -32602, message: "Invalid params: missing uri", req: req)
        }
        guard let sid = mcpResourceSubscriberId(req: req) else {
            return try await serveRpcError(id: id, code: -32603, message: "Missing subscriber context", req: req)
        }
        req.application.mcpResourceSubscriptions.unsubscribe(subscriberId: sid, uri: uri)
        return try await serveSuccess(
            JsonRpcDataResult(jsonrpc: "2.0", id: id, result: MCPJsonEmpty()),
            req: req
        )
    }

    private static func handlePromptsList(req: Request, project: Project, params: JSONRPCParams?, id: JSONRPCId?) async throws -> MCPDispatchOutput {
        struct Payload: Content {
            let jsonrpc: String
            let id: JSONRPCId?
            let result: PromptsListResult
        }
        guard let releaseId = project.activeReleaseId else {
            if params?.cursor != nil {
                return try await serveRpcError(id: id, code: -32602, message: "Invalid pagination cursor", req: req)
            }
            return try await serveSuccess(
                Payload(jsonrpc: "2.0", id: id, result: PromptsListResult(prompts: [], nextCursor: nil)),
                req: req
            )
        }
        let compiledSkillIds = try await MCPCatalogService.readyCompiledSkillIds(releaseId: releaseId, db: req.db)
        let caps = try await MCPCatalogService.capabilityDefs(
            compiledSkillIds: compiledSkillIds,
            types: ["prompt"],
            db: req.db
        )
        let prompts = caps.map { cap in
            let compiled = cap.compiledSkill
            let hints = McpCatalogMarkdown.routingHints(for: compiled)
            let desc = MCPAgentCopy.toolDescription(baseSummary: compiled.summary, hints: hints)
            return MCPPrompt(
                name: cap.capabilityName,
                description: desc,
                arguments: nil
            )
        }.sorted { $0.name < $1.name }
        let page: MCPPaginationPage<MCPPrompt>
        do {
            page = try MCPPaginator.page(
                prompts,
                cursor: params?.cursor,
                scope: "prompts:\(project.id!.uuidString):\(releaseId.uuidString)"
            )
        } catch {
            return try await serveRpcError(id: id, code: -32602, message: "Invalid pagination cursor", req: req)
        }
        return try await serveSuccess(
            Payload(jsonrpc: "2.0", id: id, result: PromptsListResult(prompts: page.items, nextCursor: page.nextCursor)),
            req: req
        )
    }

    private static func handlePromptsGet(req: Request, project: Project, params: JSONRPCParams?, id: JSONRPCId?) async throws -> MCPDispatchOutput {
        struct Payload: Content {
            let jsonrpc: String
            let id: JSONRPCId?
            let result: PromptGetResult
        }
        guard let name = params?.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return try await serveRpcError(id: id, code: -32602, message: "Invalid params: missing name", req: req)
        }
        if name.contains(":") {
            return try await serveRpcError(id: id, code: -32602, message: "Prompt not found", req: req)
        }
        req.logger.mcpTrace("mcp prompts/get name=\(name)")
        guard let releaseId = project.activeReleaseId else {
            return try await serveRpcError(id: id, code: -32602, message: "No active release", req: req)
        }
        let compiledSkillIds = try await MCPCatalogService.readyCompiledSkillIds(releaseId: releaseId, db: req.db)
        let caps = try await MCPCatalogService.capabilityDefs(
            compiledSkillIds: compiledSkillIds,
            types: ["prompt"],
            db: req.db
        )
        guard let cap = caps.first(where: { $0.capabilityName == name }) else {
            return try await serveRpcError(id: id, code: -32602, message: "Prompt not found", req: req)
        }
        let compiled = cap.compiledSkill
        var text = compiled.skillBody ?? compiled.summary ?? ""
        if let args = params?.arguments, !args.isEmpty {
            let lines = args.keys.sorted().map { key in
                "\(key): \(SkillRuntimeJSON.encode(args[key]!))"
            }.joined(separator: "\n")
            text = "Context:\n\(lines)\n\n\(text)"
        }
        let result = PromptGetResult(
            description: compiled.summary,
            messages: [
                PromptMessage(
                    role: "user",
                    content: PromptMessageContent(type: "text", text: text)
                )
            ]
        )
        return try await serveSuccess(Payload(jsonrpc: "2.0", id: id, result: result), req: req)
    }

    /// Tags successful or failed **invocations** of a catalog tool, resource read, or prompt fetch for dashboard metrics.
    private static func mcpCapabilityInvocationTag(method: String, params: JSONRPCParams?) -> (
        kind: String,
        key: String
    )? {
        switch method {
        case "tools/call":
            guard let name = params?.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                return nil
            }
            return ("tool", name)
        case "resources/read":
            guard let uri = params?.uri?.trimmingCharacters(in: .whitespacesAndNewlines), !uri.isEmpty else {
                return nil
            }
            return ("resource", uri)
        case "prompts/get":
            guard let name = params?.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                return nil
            }
            return ("prompt", name)
        default:
            return nil
        }
    }

    private static func mcpClientLabel(req: Request) -> String? {
        if let apiKeyRecord = req.storage[McpApiKeyRecordKey.self] {
            if let kid = apiKeyRecord.id {
                return RequestLogClientResolver.storedApiKeyReference(apiKeyId: kid)
            }
            return apiKeyRecord.keyPrefix
        }
        if let tok = req.storage[McpOAuthAccessTokenRecordKey.self] {
            let pub = tok.client.publicClientId
            let suffix = tok.subjectType == "service" ? "m2m" : "user"
            return "oauth:\(pub):\(suffix)"
        }
        return nil
    }

    private static func mcpResourceSubscriberId(req: Request) -> UUID? {
        if let apiKey = req.storage[McpApiKeyRecordKey.self], let id = apiKey.id {
            return id
        }
        if let tok = req.storage[McpOAuthAccessTokenRecordKey.self], let id = tok.id {
            return id
        }
        return nil
    }
}
