import Fluent
import Vapor

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
        } catch {
            return try await jsonRPCError(id: nil, code: -32700, message: "Parse error").encodeResponse(for: req)
        }

        let result: Response
        switch body.method {
        case "initialize":
            result = try await handleInitialize(req: req, id: body.id)
        case "tools/list":
            result = try await handleToolsList(req: req, projectId: projectId, id: body.id)
        case "tools/call":
            result = try await handleToolsCall(req: req, projectId: projectId, params: body.params, id: body.id)
        default:
            result = try await jsonRPCError(id: body.id, code: -32601, message: "Method not found").encodeResponse(for: req)
        }

        let latencyMs = Int(Date().timeIntervalSince(start) * 1000)
        let releaseId = project.activeReleaseId
        try? await RequestLog(
            projectId: projectId,
            releaseId: releaseId,
            clientId: nil,
            method: body.method,
            latencyMs: latencyMs,
            status: "200",
            errorCode: nil
        ).save(on: req.db)

        return result
    }

    private static func jsonRPCError(id: JSONRPCId?, code: Int, message: String) -> some Content {
        struct ErrorPayload: Content {
            let jsonrpc: String
            let id: JSONRPCId?
            let error: JSONRPCError
        }
        return ErrorPayload(jsonrpc: "2.0", id: id, error: JSONRPCError(code: code, message: message))
    }

    private static func handleInitialize(req: Request, id: JSONRPCId?) async throws -> Response {
        struct InitPayload: Content {
            let jsonrpc: String
            let id: JSONRPCId?
            let result: InitializeResult
        }
        let result = InitializeResult(
            protocolVersion: "2024-11-05",
            capabilities: ServerCapabilities(tools: ToolsCapability(listChanged: false)),
            serverInfo: ServerInfo(name: "MyContextProtocol", version: "1.0.0")
        )
        return try await InitPayload(jsonrpc: "2.0", id: id, result: result).encodeResponse(for: req)
    }

    private static func handleToolsList(req: Request, projectId: UUID, id: JSONRPCId?) async throws -> Response {
        struct ToolsListPayload: Content {
            let jsonrpc: String
            let id: JSONRPCId?
            let result: ToolsListResult
        }

        guard let releaseId = try await Project.find(projectId, on: req.db)?.activeReleaseId else {
            return try await ToolsListPayload(jsonrpc: "2.0", id: id, result: ToolsListResult(tools: [])).encodeResponse(for: req)
        }

        let compiledSkillIds = try await CompiledSkill.query(on: req.db)
            .filter(\.$release.$id == releaseId)
            .filter(\.$status == "ready")
            .all()
            .compactMap(\.id)

        guard !compiledSkillIds.isEmpty else {
            return try await ToolsListPayload(jsonrpc: "2.0", id: id, result: ToolsListResult(tools: [])).encodeResponse(for: req)
        }

        let capabilityDefs = try await CapabilityDef.query(on: req.db)
            .filter(\.$compiledSkill.$id ~~ compiledSkillIds)
            .filter(\.$type == "tool")
            .all()

        let tools = capabilityDefs.map { cap in
            MCPTool(
                name: cap.capabilityName,
                description: nil,
                inputSchema: InputSchema(type: "object", properties: nil)
            )
        }

        let listResult = ToolsListResult(tools: tools)
        return try await ToolsListPayload(jsonrpc: "2.0", id: id, result: listResult).encodeResponse(for: req)
    }

    private static func handleToolsCall(req: Request, projectId: UUID, params: JSONRPCParams?, id: JSONRPCId?) async throws -> Response {
        struct ToolCallPayload: Content {
            let jsonrpc: String
            let id: JSONRPCId?
            let result: ToolCallResult
        }

        guard let name = params?.name else {
            return try await jsonRPCError(id: id, code: -32602, message: "Invalid params: missing name").encodeResponse(for: req)
        }

        let content = try await ToolHandlers.handle(name: name, arguments: params?.arguments ?? [:], db: req.db, projectId: projectId)
        let toolResult = ToolCallResult(content: [ContentItem(type: "text", text: content)], isError: false)
        return try await ToolCallPayload(jsonrpc: "2.0", id: id, result: toolResult).encodeResponse(for: req)
    }
}
