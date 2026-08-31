import MCPServerKit
import Vapor

typealias JSONRPCId = MCPJSONRPCID
typealias JSONRPCRequest = MCPRequest
typealias JSONRPCParams = MCPRequestParams
typealias InitializeResult = MCPInitializeResult
typealias ServerCapabilities = MCPServerCapabilities
typealias ToolsCapability = MCPToolsCapability
typealias ResourcesCapability = MCPResourcesCapability
typealias PromptsCapability = MCPPromptsCapability
typealias ServerInfo = MCPServerInfo
typealias ToolsListResult = MCPToolsListResult
typealias MCPTool = MCPServerKit.MCPTool
typealias InputSchema = MCPInputSchema
typealias PropertySchema = MCPPropertySchema
typealias JSONValue = MCPJSONValue
typealias ToolCallResult = MCPToolCallResult
typealias ToolContentItem = MCPToolTextContent
typealias MCPToolContent = MCPServerKit.MCPToolContent
typealias MCPToolResourceLink = MCPToolResourceLinkContent
typealias ResourcesListResult = MCPResourcesListResult
typealias MCPResource = MCPServerKit.MCPResource
typealias PromptsListResult = MCPPromptsListResult
typealias MCPPrompt = MCPServerKit.MCPPrompt
typealias PromptArgument = MCPPromptArgument

extension MCPJSONRPCID: @retroactive Content {}
extension MCPRequest: @retroactive Content {}
extension MCPRequestParams: @retroactive Content {}
extension MCPJSONValue: @retroactive Content {}
extension MCPErrorObject: @retroactive Content {}
extension MCPInitializeResult: @retroactive Content {}
extension MCPServerCapabilities: @retroactive Content {}
extension MCPToolsCapability: @retroactive Content {}
extension MCPResourcesCapability: @retroactive Content {}
extension MCPPromptsCapability: @retroactive Content {}
extension MCPServerInfo: @retroactive Content {}
extension MCPToolsListResult: @retroactive Content {}
extension MCPServerKit.MCPTool: @retroactive Content {}
extension MCPJSONSchema: @retroactive Content {}
extension MCPToolIcon: @retroactive Content {}
extension MCPToolAnnotations: @retroactive Content {}
extension MCPToolTextContent: @retroactive Content {}
extension MCPServerKit.MCPToolContent: @retroactive Content {}
extension MCPToolResourceLinkContent: @retroactive Content {}
extension MCPToolCallResult: @retroactive Content {}
extension MCPResourcesListResult: @retroactive Content {}
extension MCPServerKit.MCPResource: @retroactive Content {}
extension MCPPromptsListResult: @retroactive Content {}
extension MCPServerKit.MCPPrompt: @retroactive Content {}
extension MCPPromptArgument: @retroactive Content {}

struct ResourceReadResult: Content {
    let contents: [ResourceContents]
}

struct ResourceContents: Content {
    let uri: String
    let mimeType: String?
    let text: String?
    let blob: String?

    init(uri: String, mimeType: String?, text: String? = nil, blob: String? = nil) {
        self.uri = uri
        self.mimeType = mimeType
        self.text = text
        self.blob = blob
    }

    enum CodingKeys: String, CodingKey {
        case uri, text, blob
        case mimeType = "mimeType"
    }
}

struct PromptGetResult: Content {
    let description: String?
    let messages: [PromptMessage]
}

struct PromptMessage: Content {
    let role: String
    let content: PromptMessageContent
}

struct PromptMessageContent: Content {
    let type: String
    let text: String?
}

typealias JSONRPCError = MCPErrorObject
