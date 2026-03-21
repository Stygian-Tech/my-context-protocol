import Fluent
import Vapor

struct MCPController {
    static func handle(req: Request) async throws -> Response {
        let start = Date()
        guard let project = req.storage[ProjectKey.self] else {
            return Response(status: .unauthorized, body: .init(string: "No project"))
        }

        let body: JSONRPCRequest
        do {
            body = try req.content.decode(JSONRPCRequest.self)
        } catch {
            return try await jsonRPCError(id: nil, code: -32700, message: "Parse error").encodeResponse(for: req)
        }

        let result: Response
        switch body.method {
        case "initialize":
            result = try await handleInitialize(req: req, id: body.id)
        case "tools/list":
            result = try await handleToolsList(req: req, projectId: project.id!, id: body.id)
        case "tools/call":
            result = try await handleToolsCall(req: req, projectId: project.id!, params: body.params, id: body.id)
        default:
            result = try await jsonRPCError(id: body.id, code: -32601, message: "Method not found").encodeResponse(for: req)
        }

        let latencyMs = Int(Date().timeIntervalSince(start) * 1000)
        let releaseId = project.activeReleaseId
        try? await RequestLog(
            projectId: project.id!,
            releaseId: releaseId,
            clientId: nil,
            method: body.method,
            latencyMs: latencyMs,
            status: "200",
            errorCode: nil
        ).save(on: req.db)

        return result
    }

    private static func jsonRPCError(id: Int?, code: Int, message: String) -> some Content {
        struct ErrorPayload: Content {
            let jsonrpc = "2.0"
            let id: Int?
            let error: JSONRPCError
        }
        return ErrorPayload(id: id, error: JSONRPCError(code: code, message: message))
    }

    private static func handleInitialize(req: Request, id: Int?) async throws -> Response {
        struct InitPayload: Content {
            let jsonrpc = "2.0"
            let id: Int?
            let result: InitializeResult
        }
        let result = InitializeResult(
            capabilities: ServerCapabilities(tools: ToolsCapability()),
            serverInfo: ServerInfo()
        )
        return try await InitPayload(id: id, result: result).encodeResponse(for: req)
    }

    private static func handleToolsList(req: Request, projectId: UUID, id: Int?) async throws -> Response {
        struct ToolsListPayload: Content {
            let jsonrpc = "2.0"
            let id: Int?
            let result: ToolsListResult
        }

        guard let releaseId = try await Project.find(projectId, on: req.db)?.activeReleaseId else {
            return try await ToolsListPayload(id: id, result: ToolsListResult(tools: [])).encodeResponse(for: req)
        }

        let compiledSkillIds = try await CompiledSkill.query(on: req.db)
            .filter(\.$release.$id == releaseId)
            .filter(\.$status == "ready")
            .all()
            .compactMap(\.id)

        guard !compiledSkillIds.isEmpty else {
            return try await ToolsListPayload(id: id, result: ToolsListResult(tools: [])).encodeResponse(for: req)
        }

        let capabilityDefs = try await CapabilityDef.query(on: req.db)
            .filter(\.$compiledSkill.$id ~~ compiledSkillIds)
            .filter(\.$type == "tool")
            .all()

        let tools = capabilityDefs.map { cap in
            MCPTool(
                name: cap.capabilityName,
                description: nil,
                inputSchema: InputSchema(properties: nil)
            )
        }

        let result = ToolsListResult(tools: tools)
        return try await ToolsListPayload(id: id, result: result).encodeResponse(for: req)
    }

    private static func handleToolsCall(req: Request, projectId: UUID, params: JSONRPCParams?, id: Int?) async throws -> Response {
        struct ToolCallPayload: Content {
            let jsonrpc = "2.0"
            let id: Int?
            let result: ToolCallResult
        }

        guard let name = params?.name else {
            return try await jsonRPCError(id: id, code: -32602, message: "Invalid params: missing name").encodeResponse(for: req)
        }

        let content = try await ToolHandlers.handle(name: name, arguments: params?.arguments ?? [:], db: req.db, projectId: projectId)
        let result = ToolCallResult(content: [ContentItem(type: "text", text: content)], isError: false)
        return try await ToolCallPayload(id: id, result: result).encodeResponse(for: req)
    }
}
