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
        #expect(p.arguments == ["a": "1"])
        #expect(p.uri == nil)
    }

    @Test("JSONRPCParams nested arguments coerce numbers and bools")
    func paramsNested() throws {
        let json = #"{"arguments":{"s":"x","i":3,"b":true,"d":1.5}}"#.data(using: .utf8)!
        let p = try JSONDecoder().decode(JSONRPCParams.self, from: json)
        #expect(p.arguments?["s"] == "x")
        #expect(p.arguments?["i"] == "3")
        #expect(p.arguments?["b"] == "true")
        #expect(p.arguments?["d"] == "1.5")
    }

    @Test("JSONRPCRequest full envelope")
    func requestEnvelope() throws {
        let json = #"{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{"name":null}}"#.data(using: .utf8)!
        let r = try JSONDecoder().decode(JSONRPCRequest.self, from: json)
        #expect(r.jsonrpc == "2.0")
        #expect(r.method == "tools/list")
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
