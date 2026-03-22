import Foundation
import Vapor

// MARK: - JSON-RPC 2.0 id (number, string, or null)

/// JSON-RPC 2.0 `id` — clients may send an integer, string, or null; decoding must accept all of them.
enum JSONRPCId: Content {
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
struct JSONRPCParams: Content {
    let name: String?
    let arguments: [String: String]?

    enum CodingKeys: String, CodingKey {
        case name
        case arguments
    }

    init(name: String?, arguments: [String: String]?) {
        self.name = name
        self.arguments = arguments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name)
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
}

struct ToolsCapability: Content {
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

struct InputSchema: Content {
    let type: String
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
