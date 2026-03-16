import Foundation
import Vapor

struct JSONRPCRequest: Content {
    let jsonrpc: String?
    let id: Int?
    let method: String
    let params: JSONRPCParams?
}

struct JSONRPCParams: Content {
    let name: String?
    let arguments: [String: String]?
}

struct InitializeResult: Content, Encodable {
    let protocolVersion: String = "2024-11-05"
    let capabilities: ServerCapabilities
    let serverInfo: ServerInfo
}

struct ServerCapabilities: Content {
    let tools: ToolsCapability?
}

struct ToolsCapability: Content {
    let listChanged: Bool? = false
}

struct ServerInfo: Content {
    let name: String = "MyContextProtocol"
    let version: String = "1.0.0"
}

struct ToolsListResult: Content {
    let tools: [MCPTool]
}

struct MCPTool: Content {
    let name: String
    let description: String?
    let inputSchema: InputSchema?
}

struct InputSchema: Content {
    let type: String = "object"
    let properties: [String: PropertySchema]?
}

struct PropertySchema: Content {
    let type: String?
    let description: String?
}

struct ToolCallResult: Content {
    let content: [ContentItem]
    let isError: Bool?
}

struct ContentItem: Content {
    let type: String
    let text: String?
}

struct JSONRPCError: Content {
    let code: Int
    let message: String
}

