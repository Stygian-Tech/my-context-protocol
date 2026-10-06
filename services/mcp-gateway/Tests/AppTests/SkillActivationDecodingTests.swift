import Foundation
import Testing
@testable import App

@Suite("Skill activation metadata decoding")
struct SkillActivationDecodingTests {
    @Test("Metadata activation accepts omitted routing lists")
    func omittedLists() throws {
        let patch = try JSONDecoder().decode(
            SkillRuntimeOverridePatch.self,
            from: Data(#"{"activation":{"mode":"explicit","intents":[]}}"#.utf8)
        )
        #expect(patch.activation == SkillActivation(mode: .explicit, intents: [], events: [], tags: [], examples: []))

        let minimal = try JSONDecoder().decode(SkillActivation.self, from: Data(#"{"mode":"intent"}"#.utf8))
        #expect(minimal == SkillActivation(mode: .intent, intents: [], events: [], tags: [], examples: []))
    }

    @Test("Provided activation lists survive decoding and encoding")
    func providedLists() throws {
        let expected = SkillActivation(
            mode: .event,
            intents: ["review a query"],
            events: ["database-change"],
            tags: ["postgres"],
            examples: ["Review this index"]
        )
        let decoded = try JSONDecoder().decode(
            SkillActivation.self,
            from: Data(#"{"mode":"event","intents":["review a query"],"events":["database-change"],"tags":["postgres"],"examples":["Review this index"]}"#.utf8)
        )
        #expect(decoded == expected)
        #expect(try JSONDecoder().decode(SkillActivation.self, from: JSONEncoder().encode(decoded)) == expected)
    }

    @Test("Malformed supplied routing lists are rejected", arguments: ["intents", "events", "tags", "examples"])
    func malformedLists(field: String) throws {
        for invalid in [#""value""#, "[1]", "{}", "null"] {
            let payload = Data("{\"mode\":\"explicit\",\"\(field)\":\(invalid)}".utf8)
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(SkillActivation.self, from: payload)
            }
        }
    }

    @Test("Activation mode remains required and validated", arguments: [#"{}"#, #"{"mode":"sometimes"}"#, #"{"mode":null}"#])
    func invalidMode(payload: String) throws {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(SkillActivation.self, from: Data(payload.utf8))
        }
    }
}
