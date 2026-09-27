import Foundation
import Testing
import Vapor
@testable import App

@Suite("JSON-RPC decode")
struct JSONRPCRequestDecodeTests {
    @Test("JSONRPCId decodes int string and null")
    func jsonRpcId() throws {
        let dec = JSONDecoder()
        #expect(try dec.decode(JSONRPCId.self, from: Data("42".utf8)) == .int(42))
        #expect(try dec.decode(JSONRPCId.self, from: Data("\"x\"".utf8)) == .string("x"))
        #expect(try dec.decode(JSONRPCId.self, from: Data("null".utf8)) == .null)
    }

    @Test("JSONRPCId encode round-trip")
    func jsonRpcIdEncode() throws {
        let enc = JSONEncoder()
        let dec = JSONDecoder()
        for id in [JSONRPCId.int(7), JSONRPCId.string("ab"), JSONRPCId.null] {
            let data = try enc.encode(id)
            let back = try dec.decode(JSONRPCId.self, from: data)
            #expect(back == id)
        }
    }

    @Test("JSONRPCParams flat arguments map")
    func paramsFlat() throws {
        let json = #"{"name":"n","arguments":{"a":"1"}}"#.data(using: .utf8)!
        let p = try JSONDecoder().decode(JSONRPCParams.self, from: json)
        #expect(p.name == "n")
        #expect(p.arguments == ["a": .string("1")])
        #expect(p.stringArguments == ["a": "1"])
        #expect(p.uri == nil)
    }

    @Test("JSONRPCParams preserves native nested arguments")
    func paramsNested() throws {
        let json = #"{"arguments":{"s":"x","i":3,"b":true,"d":1.5,"nil":null,"array":["a",2],"object":{"enabled":false}}}"#.data(using: .utf8)!
        let p = try JSONDecoder().decode(JSONRPCParams.self, from: json)
        #expect(p.arguments?["s"] == .string("x"))
        #expect(p.arguments?["i"] == .integer(3))
        #expect(p.arguments?["b"] == .bool(true))
        #expect(p.arguments?["d"] == .number(1.5))
        #expect(p.arguments?["nil"] == .null)
        #expect(p.arguments?["array"] == .array([.string("a"), .integer(2)]))
        #expect(p.arguments?["object"] == .object(["enabled": .bool(false)]))
        #expect(p.stringArguments == ["s": "x", "i": "3", "b": "true", "d": "1.5"])

        let roundTrip = try JSONDecoder().decode(
            JSONRPCParams.self,
            from: JSONEncoder().encode(p)
        )
        #expect(roundTrip == p)
    }

    @Test("JSONRPCRequest full envelope")
    func requestEnvelope() throws {
        let json = #"{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{"name":null}}"#.data(using: .utf8)!
        let r = try JSONDecoder().decode(JSONRPCRequest.self, from: json)
        #expect(r.jsonrpc == "2.0")
        #expect(r.method == "tools/list")
    }

    @Test("List cursors decode and round-trip")
    func listCursor() throws {
        let json = #"{"cursor":"opaque-page-2"}"#.data(using: .utf8)!
        let params = try JSONDecoder().decode(JSONRPCParams.self, from: json)
        #expect(params.cursor == "opaque-page-2")
        #expect(try JSONDecoder().decode(JSONRPCParams.self, from: JSONEncoder().encode(params)) == params)
    }

    @Test("InputSchema fromCapabilitySchemaJson defaults on empty")
    func inputSchemaDefault() {
        let s = InputSchema.fromCapabilitySchemaJson(nil)
        #expect(s.type == "object")
        #expect(s.properties?.isEmpty == true)
    }

    @Test("InputSchema fromCapabilitySchemaJson parses valid JSON")
    func inputSchemaParse() {
        let raw = #"{"type":"object","properties":{"x":{"type":"string"}}}"#
        let s = InputSchema.fromCapabilitySchemaJson(raw)
        #expect(s.type == "object")
        #expect(s.properties?["x"] != nil)
    }
}
