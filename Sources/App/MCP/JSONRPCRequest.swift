import Foundation
import Vapor

// MARK: - JSON-RPC 2.0 id (number, string, or null)

/// JSON-RPC 2.0 `id` — clients may send an integer, string, or null; decoding must accept all of them.
enum JSONRPCId: Content, Equatable {
    case int(Int)
    case string(String)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let i = try? container.decode(Int.self) {
            self = .int(i)
            return
        }
        if let s = try? container.decode(String.self) {
            self = .string(s)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "JSON-RPC id must be number, string, or null"
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let i): try container.encode(i)
        case .string(let s): try container.encode(s)
        case .null: try container.encodeNil()
        }
    }
}

// MARK: - Request

struct JSONRPCRequest: Content {
    let jsonrpc: String?
    let id: JSONRPCId?
    let method: String
    let params: JSONRPCParams?
}

/// `tools/call` params: `arguments` is a JSON object; values are often strings but may be numbers/bools.
/// `resources/read` includes `uri`. `prompts/get` uses `name` and optional `arguments`.
struct JSONRPCParams: Content {
    let name: String?
    let arguments: [String: String]?
    let uri: String?

    enum CodingKeys: String, CodingKey {
        case name
        case arguments
        case uri
    }

    init(name: String?, arguments: [String: String]?, uri: String? = nil) {
        self.name = name
        self.arguments = arguments
        self.uri = uri
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        uri = try c.decodeIfPresent(String.self, forKey: .uri)
        if let flat = try? c.decode([String: String].self, forKey: .arguments) {
            arguments = flat
        } else if c.contains(.arguments) {
            let nested = try c.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: .arguments)
            var out: [String: String] = [:]
            for key in nested.allKeys {
                if let s = try? nested.decode(String.self, forKey: key) {
                    out[key.stringValue] = s
                } else if let i = try? nested.decode(Int.self, forKey: key) {
                    out[key.stringValue] = String(i)
                } else if let b = try? nested.decode(Bool.self, forKey: key) {
                    out[key.stringValue] = String(b)
                } else if let d = try? nested.decode(Double.self, forKey: key) {
                    out[key.stringValue] = String(d)
                }
            }
            arguments = out.isEmpty ? nil : out
        } else {
            arguments = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(arguments, forKey: .arguments)
        try c.encodeIfPresent(uri, forKey: .uri)
    }
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    init?(stringValue: String) { self.stringValue = stringValue }
    var intValue: Int?
    init?(intValue: Int) { nil }
}

// MARK: - Responses (no default values on `let` — otherwise synthesized Decodable skips keys and breaks Content)

struct InitializeResult: Content {
    let protocolVersion: String
    let capabilities: ServerCapabilities
    let serverInfo: ServerInfo
}

struct ServerCapabilities: Content {
    let tools: ToolsCapability?
    let resources: ResourcesCapability?
    let prompts: PromptsCapability?
}

struct ToolsCapability: Content {
    let listChanged: Bool?
}

struct ResourcesCapability: Content {
    let subscribe: Bool?
    let listChanged: Bool?
}

struct PromptsCapability: Content {
    let listChanged: Bool?
}

struct ServerInfo: Content {
    let name: String
    let version: String
}

struct ToolsListResult: Content {
    let tools: [MCPTool]
}

struct MCPTool: Content {
    let name: String
    let description: String?
    let inputSchema: InputSchema?
}

struct InputSchema: Content, Codable {
    let type: String
    let properties: [String: PropertySchema]?
}

struct PropertySchema: Content, Codable {
    let type: String?
    let description: String?
}

extension InputSchema {
    static func fromCapabilitySchemaJson(_ raw: String?) -> InputSchema {
        guard let raw, let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(InputSchema.self, from: data) else {
            return InputSchema(type: "object", properties: [:])
        }
        return decoded
    }
}

// MARK: - Resources

struct ResourcesListResult: Content {
    let resources: [MCPResource]
    let nextCursor: String?
}

struct MCPResource: Content {
    let uri: String
    let name: String?
    let description: String?
    let mimeType: String?
    /// Optional agent hints (also in `schema_json`); snake_case matches SKILL front matter keys.
    let useWhen: [String]?
    let avoidWhen: [String]?
    let failureModes: [String]?
    let invokeFirst: Bool?

    enum CodingKeys: String, CodingKey {
        case uri, name, description
        case mimeType = "mimeType"
        case useWhen = "use_when"
        case avoidWhen = "avoid_when"
        case failureModes = "failure_modes"
        case invokeFirst = "invoke_first"
    }
}

struct ResourceReadResult: Content {
    let contents: [ResourceContents]
}

struct ResourceContents: Content {
    let uri: String
    let mimeType: String?
    let text: String?

    enum CodingKeys: String, CodingKey {
        case uri, text
        case mimeType = "mimeType"
    }
}

// MARK: - Prompts

struct PromptsListResult: Content {
    let prompts: [MCPPrompt]
}

struct MCPPrompt: Content {
    let name: String
    let description: String?
    let arguments: [PromptArgument]?
}

struct PromptArgument: Content {
    let name: String
    let description: String?
    let required: Bool?
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
