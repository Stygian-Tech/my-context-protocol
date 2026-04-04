import Fluent
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

        let body: JSONRPCRequest
        do {
            body = try req.content.decode(JSONRPCRequest.self)
            req.logger.devTrace("mcp_rpc decoded method=\(body.method) projectId=\(projectId.uuidString)")
        } catch {
            req.logger.mcpTrace("mcp_rpc decode_failed projectId=\(projectId.uuidString)")
            let res = try await jsonRPCError(id: nil, code: -32700, message: "Parse error").encodeResponse(for: req)
            let latencyMs = Int(Date().timeIntervalSince(start) * 1000)
            try? await RequestLog(
                projectId: projectId,
                releaseId: project.activeReleaseId,
                clientId: nil,
                method: "parse_error",
                latencyMs: latencyMs,
                status: String(res.status.code),
                errorCode: "-32700",
                errorMessage: "JSON-RPC body could not be decoded"
            ).save(on: req.db)
            return res
        }

        let out: MCPDispatchOutput
        switch body.method {
        case "initialize":
            req.logger.mcpTrace("mcp dispatch handler=initialize projectId=\(projectId.uuidString)")
            out = try await handleInitialize(req: req, id: body.id)
        case "tools/list":
            req.logger.mcpTrace("mcp dispatch handler=tools/list projectId=\(projectId.uuidString)")
            out = try await handleToolsList(req: req, projectId: projectId, id: body.id)
        case "tools/call":
            req.logger.mcpTrace("mcp dispatch handler=tools/call projectId=\(projectId.uuidString)")
            out = try await handleToolsCall(req: req, projectId: projectId, params: body.params, id: body.id)
        case "resources/list":
            req.logger.mcpTrace("mcp dispatch handler=resources/list projectId=\(projectId.uuidString)")
            out = try await handleResourcesList(req: req, projectId: projectId, id: body.id)
        case "resources/read":
            req.logger.mcpTrace("mcp dispatch handler=resources/read projectId=\(projectId.uuidString)")
            out = try await handleResourcesRead(req: req, projectId: projectId, params: body.params, id: body.id)
        case "prompts/list":
            req.logger.mcpTrace("mcp dispatch handler=prompts/list projectId=\(projectId.uuidString)")
            out = try await handlePromptsList(req: req, projectId: projectId, id: body.id)
        case "prompts/get":
            req.logger.mcpTrace("mcp dispatch handler=prompts/get projectId=\(projectId.uuidString)")
            out = try await handlePromptsGet(req: req, projectId: projectId, params: body.params, id: body.id)
        default:
            req.logger.mcpTrace(
                "mcp dispatch handler=method_not_found projectId=\(projectId.uuidString) requestedMethod=\(body.method)"
            )
            out = try await serveRpcError(id: body.id, code: -32601, message: "Method not found", req: req)
        }

        let latencyMs = Int(Date().timeIntervalSince(start) * 1000)
        let errCodeStr = out.jsonRpcErrorCode.map { String($0) } ?? "-"
        req.logger.mcpTrace(
            "mcp_rpc done projectId=\(projectId.uuidString) method=\(body.method) httpStatus=\(out.httpStatus) jsonRpcError=\(errCodeStr) latencyMs=\(latencyMs)"
        )
        let releaseId = project.activeReleaseId
        try? await RequestLog(
            projectId: projectId,
            releaseId: releaseId,
            clientId: nil,
            method: body.method,
            latencyMs: latencyMs,
            status: String(out.httpStatus),
            errorCode: out.jsonRpcErrorCode.map { String($0) },
            errorMessage: out.jsonRpcErrorMessage
        ).save(on: req.db)

        return out.response
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

    private static func serveRpcError(id: JSONRPCId?, code: Int, message: String, req: Request) async throws -> MCPDispatchOutput {
        req.logger.mcpTrace("mcp rpc_error jsonRpcCode=\(code) message=\(message)")
        let response = try await jsonRPCError(id: id, code: code, message: message).encodeResponse(for: req)
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

    private static func handleInitialize(req: Request, id: JSONRPCId?) async throws -> MCPDispatchOutput {
        struct InitPayload: Content {
            let jsonrpc: String
            let id: JSONRPCId?
            let result: InitializeResult
        }
        let result = InitializeResult(
            protocolVersion: "2024-11-05",
            capabilities: ServerCapabilities(
                tools: ToolsCapability(listChanged: false),
                resources: ResourcesCapability(subscribe: false, listChanged: false),
                prompts: PromptsCapability(listChanged: false)
            ),
            serverInfo: ServerInfo(name: "MyContextProtocol", version: "1.0.0")
        )
        return try await serveSuccess(InitPayload(jsonrpc: "2.0", id: id, result: result), req: req)
    }

    private static func handleToolsList(req: Request, projectId: UUID, id: JSONRPCId?) async throws -> MCPDispatchOutput {
        struct ToolsListPayload: Content {
            let jsonrpc: String
            let id: JSONRPCId?
            let result: ToolsListResult
        }

        guard let releaseId = try await Project.find(projectId, on: req.db)?.activeReleaseId else {
            req.logger.mcpTrace("mcp tools/list result=empty reason=no_active_release")
            return try await serveSuccess(
                ToolsListPayload(jsonrpc: "2.0", id: id, result: ToolsListResult(tools: [])),
                req: req
            )
        }

        let compiledSkillIds = try await MCPCatalogService.readyCompiledSkillIds(releaseId: releaseId, db: req.db)
        guard !compiledSkillIds.isEmpty else {
            req.logger.mcpTrace("mcp tools/list result=empty reason=no_ready_skills releaseId=\(releaseId.uuidString)")
            return try await serveSuccess(
                ToolsListPayload(jsonrpc: "2.0", id: id, result: ToolsListResult(tools: [])),
                req: req
            )
        }

        let capabilityDefs = try await MCPCatalogService.capabilityDefs(
            compiledSkillIds: compiledSkillIds,
            types: ["tool"],
            db: req.db
        )
        req.logger.mcpTrace("mcp tools/list readySkillRows=\(compiledSkillIds.count) toolCaps=\(capabilityDefs.count)")

        let tools = capabilityDefs.map { cap in
            let compiled = cap.compiledSkill
            let trimmed = compiled.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
            let desc = (trimmed?.isEmpty == false) ? trimmed : nil
            let inputSchema = InputSchema.fromCapabilitySchemaJson(cap.schemaJson)
            return MCPTool(
                name: cap.capabilityName,
                description: desc,
                inputSchema: inputSchema
            )
        }

        let listResult = ToolsListResult(tools: tools)
        return try await serveSuccess(ToolsListPayload(jsonrpc: "2.0", id: id, result: listResult), req: req)
    }

    private static func handleToolsCall(req: Request, projectId: UUID, params: JSONRPCParams?, id: JSONRPCId?) async throws -> MCPDispatchOutput {
        struct ToolCallPayload: Content {
            let jsonrpc: String
            let id: JSONRPCId?
            let result: ToolCallResult
        }

        guard let name = params?.name else {
            return try await serveRpcError(id: id, code: -32602, message: "Invalid params: missing name", req: req)
        }
        let argKeys = (params?.arguments ?? [:]).keys.sorted().joined(separator: ",")
        req.logger.mcpTrace("mcp tools/call tool=\(name) argKeys=[\(argKeys)]")

        do {
            let content = try await ToolHandlers.handle(name: name, arguments: params?.arguments ?? [:], db: req.db, projectId: projectId)
            let toolResult = ToolCallResult(content: [ContentItem(type: "text", text: content)], isError: false)
            return try await serveSuccess(ToolCallPayload(jsonrpc: "2.0", id: id, result: toolResult), req: req)
        } catch let ToolHandlerError.unknownTool(name: unknown) {
            return try await serveRpcError(id: id, code: -32601, message: "Unknown tool: \(unknown)", req: req)
        } catch {
            let message: String
            if AppEnvironment.deployKind() == .prod {
                message = "Internal error"
                req.logger.error("MCP tools/call failed: \(String(reflecting: error))")
            } else {
                message = error.localizedDescription
            }
            return try await serveRpcError(id: id, code: -32603, message: message, req: req)
        }
    }

    private static func handleResourcesList(req: Request, projectId: UUID, id: JSONRPCId?) async throws -> MCPDispatchOutput {
        struct Payload: Content {
            let jsonrpc: String
            let id: JSONRPCId?
            let result: ResourcesListResult
        }
        guard let releaseId = try await Project.find(projectId, on: req.db)?.activeReleaseId else {
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
        }
        req.logger.mcpTrace("mcp resources/list count=\(resources.count)")
        return try await serveSuccess(
            Payload(jsonrpc: "2.0", id: id, result: ResourcesListResult(resources: resources, nextCursor: nil)),
            req: req
        )
    }

    private static func handleResourcesRead(req: Request, projectId: UUID, params: JSONRPCParams?, id: JSONRPCId?) async throws -> MCPDispatchOutput {
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
        guard let releaseId = try await Project.find(projectId, on: req.db)?.activeReleaseId else {
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

    private static func handlePromptsList(req: Request, projectId: UUID, id: JSONRPCId?) async throws -> MCPDispatchOutput {
        struct Payload: Content {
            let jsonrpc: String
            let id: JSONRPCId?
            let result: PromptsListResult
        }
        guard let releaseId = try await Project.find(projectId, on: req.db)?.activeReleaseId else {
            return try await serveSuccess(
                Payload(jsonrpc: "2.0", id: id, result: PromptsListResult(prompts: [])),
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
            MCPPrompt(
                name: cap.capabilityName,
                description: cap.compiledSkill.summary,
                arguments: nil
            )
        }
        return try await serveSuccess(
            Payload(jsonrpc: "2.0", id: id, result: PromptsListResult(prompts: prompts)),
            req: req
        )
    }

    private static func handlePromptsGet(req: Request, projectId: UUID, params: JSONRPCParams?, id: JSONRPCId?) async throws -> MCPDispatchOutput {
        struct Payload: Content {
            let jsonrpc: String
            let id: JSONRPCId?
            let result: PromptGetResult
        }
        guard let name = params?.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return try await serveRpcError(id: id, code: -32602, message: "Invalid params: missing name", req: req)
        }
        req.logger.mcpTrace("mcp prompts/get name=\(name)")
        guard let releaseId = try await Project.find(projectId, on: req.db)?.activeReleaseId else {
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
            let lines = args.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
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
}
